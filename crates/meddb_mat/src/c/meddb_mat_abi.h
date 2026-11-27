#ifndef MEDDB_MAT_ABI_H
#define MEDDB_MAT_ABI_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct meddb_mat meddb_mat;

int meddb_mat_open(const char *path, meddb_mat **out);
void meddb_mat_close(meddb_mat *file);
const char *meddb_mat_last_error(void);

int meddb_mat_nvars(const meddb_mat *file);
const char *meddb_mat_name(const meddb_mat *file, int index);
int meddb_mat_info(const meddb_mat *file, int index, int *rank,
                   unsigned long long *d0, unsigned long long *d1,
                   int *class_type, int *numeric, unsigned long long *n_elem);

int meddb_mat_read(meddb_mat *file, int index, double **data,
                   unsigned long long *d0, unsigned long long *d1, int *rank);
void meddb_mat_free(void *ptr);

#ifdef __cplusplus
}
#endif

#endif
