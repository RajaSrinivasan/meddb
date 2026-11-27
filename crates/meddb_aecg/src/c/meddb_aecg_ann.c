#include "meddb_aecg_ann.h"

#include <libxml/parser.h>
#include <libxml/tree.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

typedef struct {
    double onset;
    double duration;
    int overlay;
    char label[160];
    char description[360];
    char channel[64];
} note_t;

struct meddb_aecg_notes {
    note_t *items;
    int count;
    int cap;
};

static char last_error[512];

const char *meddb_aecg_notes_last_error(void) {
    return last_error;
}

static void set_error(const char *msg) {
    snprintf(last_error, sizeof last_error, "%s", msg ? msg : "aECG XML error");
}

static int local_is(xmlNode *node, const char *name) {
    return node && node->type == XML_ELEMENT_NODE && node->name &&
           strcmp((const char *)node->name, name) == 0;
}

static void prop_copy(xmlNode *node, const char *key, char *dst, size_t cap) {
    xmlChar *value;
    if (cap == 0) {
        return;
    }
    dst[0] = 0;
    if (!node) {
        return;
    }
    value = xmlGetProp(node, (const xmlChar *)key);
    if (!value) {
        return;
    }
    snprintf(dst, cap, "%s", (const char *)value);
    xmlFree(value);
}

static xmlNode *direct_child(xmlNode *node, const char *name) {
    if (!node) {
        return NULL;
    }
    for (xmlNode *child = node->children; child; child = child->next) {
        if (local_is(child, name)) {
            return child;
        }
    }
    return NULL;
}

static int ancestor_is(xmlNode *node, const char *name) {
    for (xmlNode *p = node; p; p = p->parent) {
        if (local_is(p, name)) {
            return 1;
        }
    }
    return 0;
}

static int parse_absolute(const char *text, double *out) {
    int year, month, day, hour, minute;
    double sec;
    struct tm stamp;
    time_t base;
    if (!text || strlen(text) < 14) {
        return -1;
    }
    if (sscanf(text, "%4d%2d%2d%2d%2d%lf", &year, &month, &day, &hour, &minute, &sec) != 6) {
        return -1;
    }
    if (year < 1900 || month < 1 || month > 12 || day < 1 || day > 31) {
        return -1;
    }
    memset(&stamp, 0, sizeof stamp);
    stamp.tm_year = year - 1900;
    stamp.tm_mon = month - 1;
    stamp.tm_mday = day;
    stamp.tm_hour = hour;
    stamp.tm_min = minute;
    stamp.tm_sec = (int)sec;
    stamp.tm_isdst = 0;
    base = timegm(&stamp);
    if (base == (time_t)-1) {
        return -1;
    }
    *out = (double)base + (sec - (double)(int)sec);
    return 0;
}

static int parse_quantity(const char *text, const char *unit, double *seconds) {
    char *end = NULL;
    double value;
    if (!text || !text[0]) {
        return -1;
    }
    value = strtod(text, &end);
    if (end == text) {
        return -1;
    }
    if (unit && strcmp(unit, "ms") == 0) {
        *seconds = value / 1000.0;
        return 0;
    }
    if (unit && (strcmp(unit, "s") == 0 || strcmp(unit, "sec") == 0)) {
        *seconds = value;
        return 0;
    }
    if ((!unit || !unit[0]) && strlen(text) < 14) {
        *seconds = value;
        return 0;
    }
    return -1;
}

static void element_text(xmlNode *node, char *dst, size_t cap) {
    if (cap == 0) {
        return;
    }
    dst[0] = 0;
    if (!node) {
        return;
    }
    for (xmlNode *child = node->children; child; child = child->next) {
        if (child->type == XML_TEXT_NODE && child->content) {
            snprintf(dst, cap, "%s", (const char *)child->content);
            while (dst[0] == ' ' || dst[0] == '\n' || dst[0] == '\t') {
                memmove(dst, dst + 1, strlen(dst));
            }
            return;
        }
    }
}

static void find_named_text(xmlNode *node, const char *name, char *dst, size_t cap) {
    if (!node || dst[0]) {
        return;
    }
    for (xmlNode *child = node->children; child; child = child->next) {
        if (!local_is(child, "") && child->type == XML_ELEMENT_NODE) {
            if (local_is(child, name)) {
                element_text(child, dst, cap);
                if (dst[0]) {
                    return;
                }
            } else if (!local_is(child, "annotation")) {
                find_named_text(child, name, dst, cap);
            }
        }
    }
}

static void author_of(xmlNode *annotation, char *dst, size_t cap) {
    dst[0] = 0;
    for (xmlNode *p = annotation; p; p = p->parent) {
        xmlNode *author;
        if (!local_is(p, "annotationSet")) {
            continue;
        }
        author = direct_child(p, "author");
        if (!author) {
            return;
        }
        find_named_text(author, "manufacturerModelName", dst, cap);
        if (!dst[0]) {
            find_named_text(author, "name", dst, cap);
        }
        return;
    }
}

static const char *pretty(const char *code, const char *display, char *buf, size_t cap) {
    const char *body;
    if (display && display[0]) {
        return display;
    }
    if (!code || !code[0]) {
        return "annotation";
    }
    if (strstr(code, "TIME_PD_QTc") || strstr(code, "QTc")) {
        return "QTc";
    }
    if (strstr(code, "TIME_PD_QT")) {
        return "QT";
    }
    if (strstr(code, "TIME_PD_QRS")) {
        return "QRS duration";
    }
    if (strstr(code, "TIME_PD_PR")) {
        return "PR";
    }
    if (strstr(code, "TIME_PD_P")) {
        return "P duration";
    }
    if (strstr(code, "ANGLE_QRS")) {
        return "QRS axis";
    }
    if (strstr(code, "ANGLE_P")) {
        return "P axis";
    }
    if (strstr(code, "ANGLE_T")) {
        return "T axis";
    }
    if (strstr(code, "PWAVE")) {
        return "P wave";
    }
    if (strstr(code, "QRST")) {
        return "QRST";
    }
    if (strstr(code, "QRS")) {
        return "QRS";
    }
    if (strstr(code, "TWAVE")) {
        return "T wave";
    }
    if (strstr(code, "SINUS")) {
        return "sinus rhythm";
    }
    if (strstr(code, "BEAT_NORMAL")) {
        return "normal beat";
    }
    body = strncmp(code, "MDC_ECG_", 8) == 0 ? code + 8 : code;
    snprintf(buf, cap, "%s", body);
    return buf;
}

static void consider_time(xmlNode *node, int *have_low, double *low, int *have_high, double *high,
                          char *lead, size_t lead_cap, int derived_stop) {
    char value[80];
    char unit[32];
    char code[80];
    double absolute = 0.0;
    double quantity = 0.0;

    if (!node || node->type != XML_ELEMENT_NODE) {
        return;
    }
    if (derived_stop && local_is(node, "annotation")) {
        return;
    }
    if (local_is(node, "low") || local_is(node, "high")) {
        prop_copy(node, "value", value, sizeof value);
        prop_copy(node, "unit", unit, sizeof unit);
        if (parse_absolute(value, &absolute) == 0) {
            if (local_is(node, "low") && !*have_low) {
                *low = absolute;
                *have_low = 1;
            }
            if (local_is(node, "high") && !*have_high) {
                *high = absolute;
                *have_high = 1;
            }
        } else if (parse_quantity(value, unit, &quantity) == 0) {
            if (local_is(node, "low") && !*have_low) {
                *low = quantity;
                *have_low = 2;
            }
            if (local_is(node, "high") && !*have_high) {
                *high = quantity;
                *have_high = 2;
            }
        }
    }
    if (lead && lead_cap > 0 && !lead[0] && local_is(node, "code")) {
        prop_copy(node, "code", code, sizeof code);
        if (strncmp(code, "MDC_ECG_LEAD_", 13) == 0) {
            snprintf(lead, lead_cap, "%s", code + 13);
        }
    }
    for (xmlNode *child = node->children; child; child = child->next) {
        consider_time(child, have_low, low, have_high, high, lead, lead_cap, 1);
    }
}

static int push_note(meddb_aecg_notes *notes, const note_t *item) {
    if (notes->count >= 4000) {
        return 0;
    }
    if (notes->count >= notes->cap) {
        int cap = notes->cap == 0 ? 64 : notes->cap * 2;
        note_t *grown = (note_t *)realloc(notes->items, (size_t)cap * sizeof(note_t));
        if (!grown) {
            return -1;
        }
        notes->items = grown;
        notes->cap = cap;
    }
    notes->items[notes->count++] = *item;
    return 0;
}

static void add_annotation(xmlNode *annotation, meddb_aecg_notes *notes, double head, int have_head) {
    xmlNode *code_node = direct_child(annotation, "code");
    xmlNode *value = direct_child(annotation, "value");
    char code[96];
    char value_code[96];
    char display[160];
    char pq[64];
    char unit[32];
    char author[80];
    char lead[64];
    char pretty_buf[160];
    int have_low = 0;
    int have_high = 0;
    double low = 0.0;
    double high = 0.0;
    int derived;
    note_t item;
    const char *label;

    prop_copy(code_node, "code", code, sizeof code);
    prop_copy(value, "code", value_code, sizeof value_code);
    prop_copy(value, "displayName", display, sizeof display);
    prop_copy(value, "value", pq, sizeof pq);
    prop_copy(value, "unit", unit, sizeof unit);
    lead[0] = 0;
    for (xmlNode *child = annotation->children; child; child = child->next) {
        consider_time(child, &have_low, &low, &have_high, &high, lead, sizeof lead, 1);
    }
    author_of(annotation, author, sizeof author);
    derived = ancestor_is(annotation, "derivedSeries");

    memset(&item, 0, sizeof item);
    label = pretty(value_code[0] ? value_code : code, display, pretty_buf, sizeof pretty_buf);
    if (derived) {
        snprintf(item.label, sizeof item.label, "representative %s", label);
    } else {
        snprintf(item.label, sizeof item.label, "%s", label);
    }
    snprintf(item.channel, sizeof item.channel, "%s", lead);

    {
        char raw[180];
        const char *shown = value_code[0] ? value_code : code;
        raw[0] = 0;
        if (shown && shown[0]) {
            snprintf(raw, sizeof raw, "%s", shown);
        }
        if (pq[0] && !value_code[0]) {
            snprintf(item.description, sizeof item.description, "%s%s%s %s%s%s",
                     author[0] ? author : "",
                     author[0] ? "; " : "",
                     raw,
                     pq,
                     unit[0] ? " " : "",
                     unit);
        } else {
            snprintf(item.description, sizeof item.description, "%s%s%s",
                     author[0] ? author : "",
                     (author[0] && raw[0]) ? "; " : "",
                     raw);
        }
    }

    if (have_low == 1 || have_high == 1) {
        if (!have_head) {
            return;
        }
        if (have_low == 1) {
            low -= head;
        }
        if (have_high == 1) {
            high -= head;
        }
    }
    if ((have_low == 1 && have_high == 2) || (have_low == 2 && have_high == 1)) {
        return;
    }
    if (have_low && have_high && high >= low) {
        item.onset = low;
        item.duration = high - low;
        item.overlay = derived ? 0 : 1;
    } else if (have_low) {
        item.onset = low;
        item.duration = 0.0;
        item.overlay = derived ? 0 : 1;
    } else if (have_high) {
        item.onset = high;
        item.duration = 0.0;
        item.overlay = derived ? 0 : 1;
    } else if (pq[0] && !value_code[0]) {
        item.onset = 0.0;
        item.duration = 0.0;
        item.overlay = 0;
    } else {
        return;
    }
    push_note(notes, &item);
}

static void walk(xmlNode *node, meddb_aecg_notes *notes, double head, int have_head) {
    for (xmlNode *child = node; child; child = child->next) {
        if (child->type != XML_ELEMENT_NODE) {
            continue;
        }
        if (local_is(child, "annotation")) {
            add_annotation(child, notes, head, have_head);
        }
        if (child->children) {
            walk(child->children, notes, head, have_head);
        }
    }
}

static int find_head(xmlNode *node, double *head) {
    for (xmlNode *child = node; child; child = child->next) {
        if (child->type != XML_ELEMENT_NODE) {
            continue;
        }
        if (local_is(child, "head")) {
            char value[80];
            prop_copy(child, "value", value, sizeof value);
            if (parse_absolute(value, head) == 0) {
                return 1;
            }
        }
        if (child->children && find_head(child->children, head)) {
            return 1;
        }
    }
    return 0;
}

int meddb_aecg_notes_load(const char *path, meddb_aecg_notes **out) {
    xmlDoc *doc;
    xmlNode *root;
    meddb_aecg_notes *notes;
    double head = 0.0;
    int have_head;

    last_error[0] = 0;
    if (out) {
        *out = NULL;
    }
    if (!path || !out) {
        set_error("missing path");
        return -1;
    }
    doc = xmlReadFile(path, NULL, XML_PARSE_NONET | XML_PARSE_NOERROR | XML_PARSE_NOWARNING);
    if (!doc) {
        set_error("cannot parse HL7 aECG XML");
        return -1;
    }
    root = xmlDocGetRootElement(doc);
    notes = (meddb_aecg_notes *)calloc(1, sizeof *notes);
    if (!notes || !root) {
        xmlFreeDoc(doc);
        free(notes);
        set_error("empty HL7 aECG document");
        return -1;
    }
    have_head = find_head(root, &head);
    walk(root, notes, head, have_head);
    xmlFreeDoc(doc);
    *out = notes;
    return 0;
}

void meddb_aecg_notes_free(meddb_aecg_notes *notes) {
    if (!notes) {
        return;
    }
    free(notes->items);
    free(notes);
}

static const note_t *item(const meddb_aecg_notes *notes, int index) {
    if (!notes || index < 0 || index >= notes->count) {
        return NULL;
    }
    return &notes->items[index];
}

int meddb_aecg_notes_count(const meddb_aecg_notes *notes) {
    return notes ? notes->count : 0;
}

int meddb_aecg_notes_overlay(const meddb_aecg_notes *notes, int index) {
    const note_t *note = item(notes, index);
    return note ? note->overlay : 0;
}

double meddb_aecg_notes_onset(const meddb_aecg_notes *notes, int index) {
    const note_t *note = item(notes, index);
    return note ? note->onset : 0.0;
}

double meddb_aecg_notes_duration(const meddb_aecg_notes *notes, int index) {
    const note_t *note = item(notes, index);
    return note ? note->duration : 0.0;
}

const char *meddb_aecg_notes_label(const meddb_aecg_notes *notes, int index) {
    const note_t *note = item(notes, index);
    return note ? note->label : "";
}

const char *meddb_aecg_notes_description(const meddb_aecg_notes *notes, int index) {
    const note_t *note = item(notes, index);
    return note ? note->description : "";
}

const char *meddb_aecg_notes_channel(const meddb_aecg_notes *notes, int index) {
    const note_t *note = item(notes, index);
    return note ? note->channel : "";
}
