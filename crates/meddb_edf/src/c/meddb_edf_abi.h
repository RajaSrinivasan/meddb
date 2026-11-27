#ifndef MEDDB_EDF_ABI_H
#define MEDDB_EDF_ABI_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct meddb_edf meddb_edf;

int meddb_edf_open(const char *path, int read_annotations, meddb_edf **out);
void meddb_edf_close(meddb_edf *file);
const char *meddb_edf_last_error(void);

int meddb_edf_filetype(const meddb_edf *file);
double meddb_edf_duration(const meddb_edf *file);
double meddb_edf_record_duration(const meddb_edf *file);
int meddb_edf_nsignals(const meddb_edf *file);
long long meddb_edf_nannotations(const meddb_edf *file);
void meddb_edf_start(const meddb_edf *file, int *year, int *month, int *day,
                     int *hour, int *minute, int *second, double *subsecond);
const char *meddb_edf_patient(const meddb_edf *file);
const char *meddb_edf_recording(const meddb_edf *file);
const char *meddb_edf_equipment(const meddb_edf *file);

const char *meddb_edf_label(const meddb_edf *file, int index);
const char *meddb_edf_units(const meddb_edf *file, int index);
const char *meddb_edf_transducer(const meddb_edf *file, int index);
const char *meddb_edf_prefilter(const meddb_edf *file, int index);
double meddb_edf_fs(const meddb_edf *file, int index);
double meddb_edf_phys_min(const meddb_edf *file, int index);
double meddb_edf_phys_max(const meddb_edf *file, int index);
int meddb_edf_dig_min(const meddb_edf *file, int index);
int meddb_edf_dig_max(const meddb_edf *file, int index);
long long meddb_edf_nsamples(const meddb_edf *file, int index);

int meddb_edf_read(meddb_edf *file, int index, long long start, int count, double *buf);
int meddb_edf_annotation(meddb_edf *file, long long index, double *onset_s,
                         double *duration_s, char *text, int text_cap);

#ifdef __cplusplus
}
#endif

#endif
