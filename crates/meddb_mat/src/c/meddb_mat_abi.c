#include "meddb_mat_abi.h"

#include <matio.h>

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MEDDB_MAT_MAX_VARS 64
#define MEDDB_MAT_NAME 128

typedef struct {
   char name[MEDDB_MAT_NAME];
   int rank;
   unsigned long long d0;
   unsigned long long d1;
   int class_type;
   int numeric;
   unsigned long long n_elem;
} meddb_mat_var;

struct meddb_mat {
   mat_t *file;
   int nvars;
   meddb_mat_var vars[MEDDB_MAT_MAX_VARS];
};

static char last_error[512];

static void set_error(const char *text) {
   snprintf(last_error, sizeof last_error, "%s", text);
}

const char *meddb_mat_last_error(void) {
   return last_error;
}

static int is_numeric(enum matio_classes class_type) {
   switch (class_type) {
      case MAT_C_DOUBLE:
      case MAT_C_SINGLE:
      case MAT_C_INT8:
      case MAT_C_UINT8:
      case MAT_C_INT16:
      case MAT_C_UINT16:
      case MAT_C_INT32:
      case MAT_C_UINT32:
      case MAT_C_INT64:
      case MAT_C_UINT64:
         return 1;
      default:
         return 0;
   }
}

int meddb_mat_open(const char *path, meddb_mat **out) {
   meddb_mat *file;
   matvar_t *var;
   if (out == NULL || path == NULL) {
      set_error("missing path");
      return -1;
   }
   *out = NULL;
   file = calloc(1, sizeof *file);
   if (file == NULL) {
      set_error("out of memory");
      return -1;
   }
   file->file = Mat_Open(path, MAT_ACC_RDONLY);
   if (file->file == NULL) {
      free(file);
      set_error("Mat_Open failed");
      return -1;
   }
   while ((var = Mat_VarReadNextInfo(file->file)) != NULL) {
      if (file->nvars < MEDDB_MAT_MAX_VARS && var->name != NULL) {
         meddb_mat_var *dst = &file->vars[file->nvars++];
         snprintf(dst->name, sizeof dst->name, "%s", var->name);
         dst->rank = var->rank;
         dst->class_type = (int)var->class_type;
         dst->numeric = is_numeric(var->class_type) && var->isComplex == 0 && var->rank >= 1 && var->rank <= 2;
         dst->d0 = var->rank >= 1 && var->dims != NULL ? (unsigned long long)var->dims[0] : 0;
         dst->d1 = var->rank >= 2 && var->dims != NULL ? (unsigned long long)var->dims[1] : 1;
         dst->n_elem = dst->d0;
         if (var->rank >= 2) {
            dst->n_elem *= dst->d1;
         }
      }
      Mat_VarFree(var);
   }
   *out = file;
   last_error[0] = '\0';
   return 0;
}

void meddb_mat_close(meddb_mat *file) {
   if (file == NULL) {
      return;
   }
   if (file->file != NULL) {
      Mat_Close(file->file);
   }
   free(file);
}

int meddb_mat_nvars(const meddb_mat *file) {
   return file == NULL ? 0 : file->nvars;
}

const char *meddb_mat_name(const meddb_mat *file, int index) {
   if (file == NULL || index < 0 || index >= file->nvars) {
      return "";
   }
   return file->vars[index].name;
}

int meddb_mat_info(const meddb_mat *file, int index, int *rank,
                   unsigned long long *d0, unsigned long long *d1,
                   int *class_type, int *numeric, unsigned long long *n_elem) {
   const meddb_mat_var *var;
   if (file == NULL || index < 0 || index >= file->nvars) {
      set_error("variable index out of range");
      return -1;
   }
   var = &file->vars[index];
   if (rank) *rank = var->rank;
   if (d0) *d0 = var->d0;
   if (d1) *d1 = var->d1;
   if (class_type) *class_type = var->class_type;
   if (numeric) *numeric = var->numeric;
   if (n_elem) *n_elem = var->n_elem;
   return 0;
}

static int convert(const matvar_t *var, double *dst, unsigned long long n) {
   unsigned long long i;
   if (var->data == NULL) {
      return -1;
   }
   switch (var->class_type) {
      case MAT_C_DOUBLE: {
         const double *src = var->data;
         memcpy(dst, src, (size_t)n * sizeof(double));
         return 0;
      }
      case MAT_C_SINGLE: {
         const float *src = var->data;
         for (i = 0; i < n; i++) dst[i] = src[i];
         return 0;
      }
      case MAT_C_INT8: {
         const int8_t *src = var->data;
         for (i = 0; i < n; i++) dst[i] = src[i];
         return 0;
      }
      case MAT_C_UINT8: {
         const uint8_t *src = var->data;
         for (i = 0; i < n; i++) dst[i] = src[i];
         return 0;
      }
      case MAT_C_INT16: {
         const int16_t *src = var->data;
         for (i = 0; i < n; i++) dst[i] = src[i];
         return 0;
      }
      case MAT_C_UINT16: {
         const uint16_t *src = var->data;
         for (i = 0; i < n; i++) dst[i] = src[i];
         return 0;
      }
      case MAT_C_INT32: {
         const int32_t *src = var->data;
         for (i = 0; i < n; i++) dst[i] = src[i];
         return 0;
      }
      case MAT_C_UINT32: {
         const uint32_t *src = var->data;
         for (i = 0; i < n; i++) dst[i] = src[i];
         return 0;
      }
      case MAT_C_INT64: {
         const int64_t *src = var->data;
         for (i = 0; i < n; i++) dst[i] = (double)src[i];
         return 0;
      }
      case MAT_C_UINT64: {
         const uint64_t *src = var->data;
         for (i = 0; i < n; i++) dst[i] = (double)src[i];
         return 0;
      }
      default:
         return -1;
   }
}

int meddb_mat_read(meddb_mat *file, int index, double **data,
                   unsigned long long *d0, unsigned long long *d1, int *rank) {
   matvar_t *var;
   unsigned long long n;
   double *buf;
   if (file == NULL || data == NULL || index < 0 || index >= file->nvars) {
      set_error("invalid mat read");
      return -1;
   }
   if (!file->vars[index].numeric) {
      set_error("variable is not a numeric matrix");
      return -1;
   }
   var = Mat_VarRead(file->file, file->vars[index].name);
   if (var == NULL) {
      set_error("Mat_VarRead failed");
      return -1;
   }
   n = file->vars[index].n_elem;
   if (var->rank >= 1 && var->dims != NULL) {
      n = (unsigned long long)var->dims[0];
      if (var->rank >= 2) {
         n *= (unsigned long long)var->dims[1];
      }
   }
   buf = malloc((size_t)(n == 0 ? 1 : n) * sizeof(double));
   if (buf == NULL) {
      Mat_VarFree(var);
      set_error("out of memory");
      return -1;
   }
   if (n > 0 && convert(var, buf, n) != 0) {
      free(buf);
      Mat_VarFree(var);
      set_error("unsupported MATLAB class");
      return -1;
   }
   if (d0) *d0 = var->rank >= 1 && var->dims ? (unsigned long long)var->dims[0] : 0;
   if (d1) *d1 = var->rank >= 2 && var->dims ? (unsigned long long)var->dims[1] : 1;
   if (rank) *rank = var->rank;
   *data = buf;
   Mat_VarFree(var);
   return 0;
}

void meddb_mat_free(void *ptr) {
   free(ptr);
}
