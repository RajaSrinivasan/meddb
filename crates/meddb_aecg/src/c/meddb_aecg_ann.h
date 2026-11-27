#ifndef MEDDB_AECG_ANN_H
#define MEDDB_AECG_ANN_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct meddb_aecg_notes meddb_aecg_notes;

int meddb_aecg_notes_load(const char *path, meddb_aecg_notes **out);
void meddb_aecg_notes_free(meddb_aecg_notes *notes);
const char *meddb_aecg_notes_last_error(void);

int meddb_aecg_notes_count(const meddb_aecg_notes *notes);
int meddb_aecg_notes_overlay(const meddb_aecg_notes *notes, int index);
double meddb_aecg_notes_onset(const meddb_aecg_notes *notes, int index);
double meddb_aecg_notes_duration(const meddb_aecg_notes *notes, int index);
const char *meddb_aecg_notes_label(const meddb_aecg_notes *notes, int index);
const char *meddb_aecg_notes_description(const meddb_aecg_notes *notes, int index);
const char *meddb_aecg_notes_channel(const meddb_aecg_notes *notes, int index);

#ifdef __cplusplus
}
#endif

#endif
