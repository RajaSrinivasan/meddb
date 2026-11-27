#include "meddb_biosig_abi.h"

#include <biosig.h>

#include <ctype.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

struct meddb_biosig {
    HDRTYPE *hdr;
    char patient[512];
    char start[40];
    char **statements;
    int nstatements;
    double *cache;
    long long cache_start;
    int cache_count;
    int cache_rows;
};

static char last_error[512];

static void set_error(const char *msg) {
    snprintf(last_error, sizeof last_error, "%s", msg ? msg : "biosig error");
}

const char *meddb_biosig_last_error(void) {
    return last_error;
}

static const char *nz(const char *s) {
    return s ? s : "";
}

static void copy_clean(char *dst, size_t cap, const char *src) {
    size_t w = 0;
    if (cap == 0) {
        return;
    }
    if (!src) {
        dst[0] = 0;
        return;
    }
    for (size_t i = 0; src[i] != 0 && w + 2 < cap; i++) {
        unsigned char c = (unsigned char)src[i];
        if (c == 0x1f) {
            if (w + 2 < cap) {
                dst[w++] = ',';
                dst[w++] = ' ';
            }
            continue;
        }
        if (c < 32 || c == 127) {
            dst[w++] = ' ';
            continue;
        }
        dst[w++] = (char)c;
    }
    while (w > 0 && dst[w - 1] == ' ') {
        w--;
    }
    dst[w] = 0;
}

static char *latin1_text(const uint8_t *bytes, size_t n) {
    char *out = (char *)malloc(n * 2 + 1);
    size_t w = 0;
    size_t printable = 0;
    if (!out) {
        return NULL;
    }
    for (size_t i = 0; i < n; i++) {
        unsigned char c = bytes[i];
        if (c == 0) {
            break;
        }
        if (c < 32 || c == 127) {
            if (w > 0 && out[w - 1] != ' ') {
                out[w++] = ' ';
            }
            continue;
        }
        if (c < 0x80) {
            out[w++] = (char)c;
            if (!isspace(c)) {
                printable++;
            }
        } else {
            out[w++] = (char)(0xC0 | (c >> 6));
            out[w++] = (char)(0x80 | (c & 0x3F));
            printable++;
        }
    }
    while (w > 0 && out[w - 1] == ' ') {
        w--;
    }
    out[w] = 0;
    if (w == 0 || printable == 0) {
        free(out);
        return NULL;
    }
    return out;
}

static int mostly_rule(const char *text) {
    size_t marks = 0;
    size_t other = 0;
    for (const char *p = text; *p; p++) {
        unsigned char c = (unsigned char)*p;
        if (c == ' ' || c == '=' || c == '-' || c == '+' || c == '|' || c == '*') {
            marks++;
        } else {
            other++;
        }
    }
    return other < 4;
}

static char *clean_statement(char *text) {
    char *body = text;
    size_t n;
    if (!text) {
        return NULL;
    }
    n = strlen(text);
    if (n >= 4) {
        unsigned char a = (unsigned char)text[0];
        unsigned char b = (unsigned char)text[1];
        int code = (isupper(a) || isdigit(a)) && (isupper(b) || isdigit(b));
        if (code) {
            body = text + 2;
            while (*body == ' ') {
                body++;
            }
        }
    }
    if (mostly_rule(body)) {
        free(text);
        return NULL;
    }
    if (body != text) {
        memmove(text, body, strlen(body) + 1);
    }
    return text;
}

static void parse_section8(meddb_biosig *file) {
    const uint8_t *p;
    uint32_t len;
    unsigned n;
    const uint8_t *q;
    const uint8_t *end;
    unsigned year;

    if (!file->hdr || file->hdr->SCP.Section8Length < 9 || !file->hdr->SCP.Section8) {
        return;
    }
    p = file->hdr->SCP.Section8;
    len = file->hdr->SCP.Section8Length;
    year = (unsigned)p[1] | ((unsigned)p[2] << 8);
    n = p[8];
    if (year < 1980 || year > 2100 || n > 200) {
        return;
    }
    q = p + 9;
    end = p + len;
    file->statements = (char **)calloc(n ? n : 1, sizeof(char *));
    if (!file->statements) {
        return;
    }
    for (unsigned i = 0; i < n && q + 3 <= end; i++) {
        unsigned sl = (unsigned)q[1] | ((unsigned)q[2] << 8);
        q += 3;
        if (sl > 8192 || q + sl > end) {
            break;
        }
        file->statements[file->nstatements] = clean_statement(latin1_text(q, sl));
        if (file->statements[file->nstatements]) {
            file->nstatements++;
        }
        q += sl;
    }
}

int meddb_biosig_open(const char *path, meddb_biosig **out) {
    HDRTYPE *hdr;
    int err;
    long ns;
    struct tm stamp;
    meddb_biosig *file;

    last_error[0] = 0;
    if (out) {
        *out = NULL;
    }
    if (!path || !out) {
        set_error("missing path");
        return -1;
    }
    hdr = constructHDR(0, 0);
    if (!hdr) {
        set_error("out of memory");
        return -1;
    }
    hdr->FLAG.ANONYMOUS = 0;
    hdr = sopen(path, "r", hdr);
    if (!hdr) {
        set_error("cannot open file");
        return -1;
    }
    err = biosig_check_error(hdr);
    ns = biosig_get_number_of_channels(hdr);
    if (err != 0 || ns <= 0) {
        char *msg = biosig_get_errormsg(hdr);
        set_error(msg && msg[0] ? msg : "cannot open file");
        free(msg);
        sclose(hdr);
        destructHDR(hdr);
        return -1;
    }
    if (ns > 256) {
        set_error("too many channels");
        sclose(hdr);
        destructHDR(hdr);
        return -1;
    }
    file = (meddb_biosig *)calloc(1, sizeof *file);
    if (!file) {
        set_error("out of memory");
        sclose(hdr);
        destructHDR(hdr);
        return -1;
    }
    file->hdr = hdr;
    file->cache_start = -1;
    copy_clean(file->patient, sizeof file->patient, biosig_get_patient_name(hdr));
    memset(&stamp, 0, sizeof stamp);
    if (biosig_get_startdatetime(hdr, &stamp) == 0 && stamp.tm_year + 1900 >= 1900) {
        snprintf(file->start, sizeof file->start, "%04d-%02d-%02dT%02d:%02d:%02d",
                 stamp.tm_year + 1900, stamp.tm_mon + 1, stamp.tm_mday,
                 stamp.tm_hour, stamp.tm_min, stamp.tm_sec);
    }
    parse_section8(file);
    *out = file;
    return 0;
}

void meddb_biosig_close(meddb_biosig *file) {
    if (!file) {
        return;
    }
    if (file->statements) {
        for (int i = 0; i < file->nstatements; i++) {
            free(file->statements[i]);
        }
        free(file->statements);
    }
    free(file->cache);
    if (file->hdr) {
        sclose(file->hdr);
        destructHDR(file->hdr);
    }
    free(file);
}

const char *meddb_biosig_format(const meddb_biosig *file) {
    enum FileFormat fmt;
    if (!file || !file->hdr) {
        return "";
    }
    fmt = biosig_get_filetype(file->hdr);
    return nz(GetFileTypeString(fmt));
}

const char *meddb_biosig_patient(const meddb_biosig *file) {
    return file ? file->patient : "";
}

const char *meddb_biosig_patient_id(const meddb_biosig *file) {
    return file && file->hdr ? nz(biosig_get_patient_id(file->hdr)) : "";
}

const char *meddb_biosig_recording_id(const meddb_biosig *file) {
    return file && file->hdr ? nz(biosig_get_recording_id(file->hdr)) : "";
}

const char *meddb_biosig_manufacturer(const meddb_biosig *file) {
    return file && file->hdr ? nz(biosig_get_manufacturer_name(file->hdr)) : "";
}

const char *meddb_biosig_model(const meddb_biosig *file) {
    return file && file->hdr ? nz(biosig_get_manufacturer_model(file->hdr)) : "";
}

const char *meddb_biosig_sw_version(const meddb_biosig *file) {
    return file && file->hdr ? nz(biosig_get_manufacturer_version(file->hdr)) : "";
}

const char *meddb_biosig_serial(const meddb_biosig *file) {
    return file && file->hdr ? nz(biosig_get_manufacturer_serial_number(file->hdr)) : "";
}

const char *meddb_biosig_start(const meddb_biosig *file) {
    return file ? file->start : "";
}

static CHANNEL_TYPE *channel(const meddb_biosig *file, int index) {
    if (!file || !file->hdr || index < 0 || index >= biosig_get_number_of_channels(file->hdr)) {
        return NULL;
    }
    return biosig_get_channel(file->hdr, index);
}

static long long channel_samples(const meddb_biosig *file, int index) {
    CHANNEL_TYPE *ch = channel(file, index);
    size_t nrec;
    size_t spr;
    if (!ch) {
        return 0;
    }
    nrec = biosig_get_number_of_records(file->hdr);
    spr = biosig_channel_get_samples_per_record(ch);
    if (nrec == 0 || spr == 0) {
        return (long long)biosig_get_number_of_samples(file->hdr);
    }
    return (long long)nrec * (long long)spr;
}

double meddb_biosig_duration(const meddb_biosig *file) {
    double duration = 0.0;
    int ns;
    if (!file) {
        return 0.0;
    }
    ns = meddb_biosig_nsignals(file);
    for (int i = 0; i < ns; i++) {
        double fs = meddb_biosig_fs(file, i);
        long long n = channel_samples(file, i);
        if (fs > 0.0 && n > 0) {
            double d = (double)n / fs;
            if (d > duration) {
                duration = d;
            }
        }
    }
    return duration;
}

int meddb_biosig_nsignals(const meddb_biosig *file) {
    if (!file || !file->hdr) {
        return 0;
    }
    return (int)biosig_get_number_of_channels(file->hdr);
}

const char *meddb_biosig_label(const meddb_biosig *file, int index) {
    CHANNEL_TYPE *ch = channel(file, index);
    return ch ? nz(biosig_channel_get_label(ch)) : "";
}

const char *meddb_biosig_units(const meddb_biosig *file, int index) {
    CHANNEL_TYPE *ch = channel(file, index);
    return ch ? nz(biosig_channel_get_physdim(ch)) : "";
}

const char *meddb_biosig_transducer(const meddb_biosig *file, int index) {
    CHANNEL_TYPE *ch = channel(file, index);
    return ch ? nz(biosig_channel_get_transducer(ch)) : "";
}

double meddb_biosig_fs(const meddb_biosig *file, int index) {
    double fs;
    if (!channel(file, index)) {
        return 0.0;
    }
    fs = biosig_get_channel_samplerate(file->hdr, index);
    if (fs <= 0.0) {
        fs = biosig_get_samplerate(file->hdr);
    }
    return fs;
}

double meddb_biosig_cal(const meddb_biosig *file, int index) {
    CHANNEL_TYPE *ch = channel(file, index);
    return ch ? biosig_channel_get_cal(ch) : 0.0;
}

double meddb_biosig_off(const meddb_biosig *file, int index) {
    CHANNEL_TYPE *ch = channel(file, index);
    return ch ? biosig_channel_get_off(ch) : 0.0;
}

static void scaling(const meddb_biosig *file, int index, double *pmin, double *pmax,
                    double *dmin, double *dmax) {
    CHANNEL_TYPE *ch = channel(file, index);
    *pmin = 0.0;
    *pmax = 0.0;
    *dmin = 0.0;
    *dmax = 0.0;
    if (!ch) {
        return;
    }
    biosig_channel_get_scaling(ch, pmax, pmin, dmax, dmin);
}

double meddb_biosig_phys_min(const meddb_biosig *file, int index) {
    double pmin, pmax, dmin, dmax;
    scaling(file, index, &pmin, &pmax, &dmin, &dmax);
    if (!isfinite(pmin) || !isfinite(pmax) || !(pmax > pmin) || fabs(pmin) > 1.0e7 || fabs(pmax) > 1.0e7) {
        return 0.0;
    }
    return pmin;
}

double meddb_biosig_phys_max(const meddb_biosig *file, int index) {
    double pmin, pmax, dmin, dmax;
    scaling(file, index, &pmin, &pmax, &dmin, &dmax);
    if (!isfinite(pmin) || !isfinite(pmax) || !(pmax > pmin) || fabs(pmin) > 1.0e7 || fabs(pmax) > 1.0e7) {
        return 0.0;
    }
    return pmax;
}

int meddb_biosig_dig_min(const meddb_biosig *file, int index) {
    double pmin, pmax, dmin, dmax;
    scaling(file, index, &pmin, &pmax, &dmin, &dmax);
    if (!isfinite(dmin) || fabs(dmin) > 2.0e9) {
        return 0;
    }
    return (int)llround(dmin);
}

int meddb_biosig_dig_max(const meddb_biosig *file, int index) {
    double pmin, pmax, dmin, dmax;
    scaling(file, index, &pmin, &pmax, &dmin, &dmax);
    if (!isfinite(dmax) || fabs(dmax) > 2.0e9) {
        return 0;
    }
    return (int)llround(dmax);
}

int meddb_biosig_lead(const meddb_biosig *file, int index) {
    CHANNEL_TYPE *ch = channel(file, index);
    return ch ? (int)ch->LeadIdCode : 0;
}

long long meddb_biosig_nsamples(const meddb_biosig *file, int index) {
    return channel_samples(file, index);
}

static int load_window(meddb_biosig *file, long long start, int count) {
    uint32_t spr;
    long long rec;
    int offset;
    int need;
    int nrec;
    size_t got;
    biosig_data_type *data = NULL;
    size_t rows = 0;
    size_t cols = 0;
    int ns;
    double *copy;

    spr = file->hdr->SPR;
    if (spr == 0) {
        spr = 1;
    }
    if (start < 0) {
        start = 0;
    }
    rec = start / (long long)spr;
    offset = (int)(start % (long long)spr);
    need = count + offset;
    nrec = (need + (int)spr - 1) / (int)spr;
    if (nrec < 1) {
        nrec = 1;
    }
    if ((long long)nrec * (long long)spr > 20000000LL) {
        set_error("requested sample window is too large");
        return -1;
    }
    biosig_set_flag(file->hdr, BIOSIG_FLAG_ROW_BASED_CHANNELS);
    got = sread(NULL, (size_t)rec, (size_t)nrec, file->hdr);
    if (biosig_get_datablock(file->hdr, &data, &rows, &cols) != 0 || !data || rows == 0 || cols == 0) {
        char *msg = biosig_get_errormsg(file->hdr);
        set_error(msg && msg[0] ? msg : "cannot read samples");
        free(msg);
        return -1;
    }
    (void)got;
    ns = meddb_biosig_nsignals(file);
    if ((size_t)ns > rows) {
        ns = (int)rows;
    }
    copy = (double *)calloc((size_t)ns * (size_t)count, sizeof(double));
    if (!copy) {
        set_error("out of memory");
        return -1;
    }
    for (int ch = 0; ch < ns; ch++) {
        const double *row = data + (size_t)ch * cols;
        for (int i = 0; i < count; i++) {
            size_t src = (size_t)offset + (size_t)i;
            if (src < cols) {
                copy[(size_t)ch * (size_t)count + (size_t)i] = row[src];
            }
        }
    }
    free(file->cache);
    file->cache = copy;
    file->cache_start = start;
    file->cache_count = count;
    file->cache_rows = ns;
    return 0;
}

int meddb_biosig_read(meddb_biosig *file, int index, long long start, int count, double *buf) {
    if (!file || !file->hdr || !buf || index < 0) {
        set_error("invalid read");
        return -1;
    }
    if (count <= 0) {
        return 0;
    }
    if (!file->cache || file->cache_start != start || file->cache_count < count || index >= file->cache_rows) {
        if (load_window(file, start, count) != 0) {
            return -1;
        }
    }
    if (index >= file->cache_rows) {
        set_error("channel index out of range");
        return -1;
    }
    memcpy(buf, file->cache + (size_t)index * (size_t)file->cache_count, (size_t)count * sizeof(double));
    return count;
}

int meddb_biosig_nevents(const meddb_biosig *file) {
    if (!file || !file->hdr) {
        return 0;
    }
    return (int)biosig_get_number_of_events(file->hdr);
}

int meddb_biosig_event(const meddb_biosig *file, int index, double *onset, double *duration,
                       int *channel, char *label, int label_cap, char *desc, int desc_cap) {
    uint16_t typ = 0;
    uint16_t chn = 0;
    uint32_t pos = 0;
    uint32_t dur = 0;
    const char *text = NULL;
    const char *ged;
    double fs;

    if (!file || !file->hdr || index < 0 || (size_t)index >= biosig_get_number_of_events(file->hdr)) {
        return -1;
    }
    if (biosig_get_nth_event(file->hdr, (size_t)index, &typ, &pos, &chn, &dur, NULL, &text) != 0) {
        return -1;
    }
    fs = biosig_get_eventtable_samplerate(file->hdr);
    if (fs <= 0.0) {
        fs = biosig_get_samplerate(file->hdr);
    }
    if (fs <= 0.0) {
        fs = 1.0;
    }
    if (onset) {
        *onset = (double)pos / fs;
    }
    if (duration) {
        *duration = (double)dur / fs;
    }
    if (channel) {
        *channel = (int)chn;
    }
    ged = GetEventDescription(file->hdr, (size_t)index);
    if (label && label_cap > 0) {
        if (ged && ged[0]) {
            snprintf(label, (size_t)label_cap, "%s", ged);
        } else if (text && text[0]) {
            snprintf(label, (size_t)label_cap, "%s", text);
        } else {
            snprintf(label, (size_t)label_cap, "event-%u", typ);
        }
    }
    if (desc && desc_cap > 0) {
        if (text && text[0]) {
            snprintf(desc, (size_t)desc_cap, "%s", text);
        } else if (ged && ged[0]) {
            snprintf(desc, (size_t)desc_cap, "%s", ged);
        } else if (label) {
            snprintf(desc, (size_t)desc_cap, "%s", label);
        } else {
            desc[0] = 0;
        }
    }
    return 0;
}

int meddb_biosig_nstatements(const meddb_biosig *file) {
    return file ? file->nstatements : 0;
}

const char *meddb_biosig_statement(const meddb_biosig *file, int index) {
    if (!file || index < 0 || index >= file->nstatements || !file->statements[index]) {
        return "";
    }
    return file->statements[index];
}
