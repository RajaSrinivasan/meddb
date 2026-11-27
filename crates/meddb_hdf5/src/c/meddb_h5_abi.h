#ifndef MEDDB_H5_ABI_H
#define MEDDB_H5_ABI_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct meddb_h5 meddb_h5;

typedef struct {
   char path[512];
   char dtype[32];
   int rank;
   unsigned long long dims[4];
   unsigned long long n_elements;
} meddb_h5_node;

int meddb_h5_open(const char *path, meddb_h5 **out);
void meddb_h5_close(meddb_h5 *file);
const char *meddb_h5_last_error(void);

int meddb_h5_ndatasets(const meddb_h5 *file);
int meddb_h5_dataset(const meddb_h5 *file, int index, meddb_h5_node *node);
int meddb_h5_exists(const meddb_h5 *file, const char *path);

int meddb_h5_read_text(meddb_h5 *file, const char *path, char *buf, int cap);
int meddb_h5_read_scalar(meddb_h5 *file, const char *path, double *out);
int meddb_h5_read_waveform(meddb_h5 *file, const char *path,
                           unsigned long long start, unsigned long long count,
                           double **out, unsigned long long *n_channels,
                           unsigned long long *n_samples);
void meddb_h5_free(void *ptr);

#ifdef __cplusplus
}
#endif

#endif
