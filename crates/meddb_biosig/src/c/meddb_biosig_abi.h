#ifndef MEDDB_BIOSIG_ABI_H
#define MEDDB_BIOSIG_ABI_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct meddb_biosig meddb_biosig;

int meddb_biosig_open(const char *path, meddb_biosig **out);
void meddb_biosig_close(meddb_biosig *file);
const char *meddb_biosig_last_error(void);

const char *meddb_biosig_format(const meddb_biosig *file);
const char *meddb_biosig_patient(const meddb_biosig *file);
const char *meddb_biosig_patient_id(const meddb_biosig *file);
const char *meddb_biosig_recording_id(const meddb_biosig *file);
const char *meddb_biosig_manufacturer(const meddb_biosig *file);
const char *meddb_biosig_model(const meddb_biosig *file);
const char *meddb_biosig_sw_version(const meddb_biosig *file);
const char *meddb_biosig_serial(const meddb_biosig *file);
const char *meddb_biosig_start(const meddb_biosig *file);
double meddb_biosig_duration(const meddb_biosig *file);
int meddb_biosig_nsignals(const meddb_biosig *file);

const char *meddb_biosig_label(const meddb_biosig *file, int index);
const char *meddb_biosig_units(const meddb_biosig *file, int index);
const char *meddb_biosig_transducer(const meddb_biosig *file, int index);
double meddb_biosig_fs(const meddb_biosig *file, int index);
double meddb_biosig_cal(const meddb_biosig *file, int index);
double meddb_biosig_off(const meddb_biosig *file, int index);
double meddb_biosig_phys_min(const meddb_biosig *file, int index);
double meddb_biosig_phys_max(const meddb_biosig *file, int index);
int meddb_biosig_dig_min(const meddb_biosig *file, int index);
int meddb_biosig_dig_max(const meddb_biosig *file, int index);
int meddb_biosig_lead(const meddb_biosig *file, int index);
long long meddb_biosig_nsamples(const meddb_biosig *file, int index);

int meddb_biosig_read(meddb_biosig *file, int index, long long start, int count, double *buf);

int meddb_biosig_nevents(const meddb_biosig *file);
int meddb_biosig_event(const meddb_biosig *file, int index, double *onset, double *duration,
                       int *channel, char *label, int label_cap, char *desc, int desc_cap);

int meddb_biosig_nstatements(const meddb_biosig *file);
const char *meddb_biosig_statement(const meddb_biosig *file, int index);

#ifdef __cplusplus
}
#endif

#endif
