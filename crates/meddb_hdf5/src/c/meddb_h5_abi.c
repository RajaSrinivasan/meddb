#include "meddb_h5_abi.h"

#include <hdf5.h>

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MEDDB_H5_MAX_NODES 4096

struct meddb_h5 {
   hid_t file;
   int nnodes;
   int truncated;
   meddb_h5_node nodes[MEDDB_H5_MAX_NODES];
};

static char last_error[512];

static void set_error(const char *text) {
   snprintf(last_error, sizeof last_error, "%s", text);
}

const char *meddb_h5_last_error(void) {
   return last_error;
}

static void dtype_name(hid_t type, char *buf, size_t cap) {
   H5T_class_t class_id = H5Tget_class(type);
   size_t size = H5Tget_size(type);
   const char *kind = "other";
   switch (class_id) {
      case H5T_INTEGER:
         kind = H5Tget_sign(type) == H5T_SGN_NONE ? "uint" : "int";
         break;
      case H5T_FLOAT:
         kind = "float";
         break;
      case H5T_STRING:
         snprintf(buf, cap, "string");
         return;
      default:
         break;
   }
   snprintf(buf, cap, "%s%u", kind, (unsigned)(size * 8));
}

static void add_dataset(meddb_h5 *file, hid_t loc, const char *name, const char *path) {
   hid_t dset;
   hid_t space;
   hid_t type;
   meddb_h5_node *node;
   hsize_t dims[4];
   int rank;
   int i;
   unsigned long long n;
   if (file->nnodes >= MEDDB_H5_MAX_NODES) {
      file->truncated = 1;
      return;
   }
   dset = H5Dopen2(loc, name, H5P_DEFAULT);
   if (dset < 0) {
      return;
   }
   node = &file->nodes[file->nnodes++];
   memset(node, 0, sizeof *node);
   snprintf(node->path, sizeof node->path, "%s", path);
   space = H5Dget_space(dset);
   type = H5Dget_type(dset);
   rank = H5Sget_simple_extent_ndims(space);
   if (rank < 0) {
      rank = 0;
   }
   if (rank > 4) {
      rank = 4;
   }
   node->rank = rank;
   if (rank > 0) {
      H5Sget_simple_extent_dims(space, dims, NULL);
      n = 1;
      for (i = 0; i < rank; i++) {
         node->dims[i] = (unsigned long long)dims[i];
         n *= node->dims[i];
      }
      node->n_elements = n;
   } else {
      node->n_elements = 1;
   }
   dtype_name(type, node->dtype, sizeof node->dtype);
   H5Tclose(type);
   H5Sclose(space);
   H5Dclose(dset);
}

static void walk(meddb_h5 *file, hid_t loc, const char *path) {
   H5G_info_t info;
   hsize_t i;
   if (H5Gget_info(loc, &info) < 0) {
      return;
   }
   for (i = 0; i < info.nlinks; i++) {
      char name[256];
      char child[768];
      H5O_info_t obj;
      ssize_t nlen = H5Lget_name_by_idx(loc, ".", H5_INDEX_NAME, H5_ITER_INC, i,
                                        name, sizeof name, H5P_DEFAULT);
      if (nlen < 0) {
         continue;
      }
      if (path[0] == '\0') {
         snprintf(child, sizeof child, "/%s", name);
      } else {
         snprintf(child, sizeof child, "%s/%s", path, name);
      }
      if (H5Oget_info_by_name(loc, name, &obj, H5P_DEFAULT) < 0) {
         continue;
      }
      if (obj.type == H5O_TYPE_GROUP) {
         hid_t group = H5Gopen2(loc, name, H5P_DEFAULT);
         if (group >= 0) {
            walk(file, group, child);
            H5Gclose(group);
         }
      } else if (obj.type == H5O_TYPE_DATASET) {
         add_dataset(file, loc, name, child);
      }
   }
}

int meddb_h5_open(const char *path, meddb_h5 **out) {
   meddb_h5 *file;
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
   file->file = H5Fopen(path, H5F_ACC_RDONLY, H5P_DEFAULT);
   if (file->file < 0) {
      free(file);
      set_error("H5Fopen failed");
      return -1;
   }
   walk(file, file->file, "");
   *out = file;
   last_error[0] = '\0';
   return 0;
}

void meddb_h5_close(meddb_h5 *file) {
   if (file == NULL) {
      return;
   }
   if (file->file >= 0) {
      H5Fclose(file->file);
   }
   free(file);
}

int meddb_h5_ndatasets(const meddb_h5 *file) {
   return file == NULL ? 0 : file->nnodes;
}

int meddb_h5_dataset(const meddb_h5 *file, int index, meddb_h5_node *node) {
   if (file == NULL || node == NULL || index < 0 || index >= file->nnodes) {
      set_error("dataset index out of range");
      return -1;
   }
   *node = file->nodes[index];
   return 0;
}

int meddb_h5_exists(const meddb_h5 *file, const char *path) {
   htri_t exists;
   if (file == NULL || path == NULL) {
      return 0;
   }
   exists = H5Lexists(file->file, path, H5P_DEFAULT);
   return exists > 0;
}

static int mostly_text(const int8_t *bytes, unsigned long long n) {
   unsigned long long i;
   unsigned long long ok = 0;
   if (n == 0 || n > 4096) {
      return 0;
   }
   for (i = 0; i < n; i++) {
      unsigned char c = (unsigned char)bytes[i];
      if (c == 0 || (c >= 9 && c <= 13) || (c >= 32 && c < 127)) {
         ok++;
      }
   }
   return ok * 10 >= n * 8;
}

int meddb_h5_read_text(meddb_h5 *file, const char *path, char *buf, int cap) {
   hid_t dset, space, type;
   H5T_class_t class_id;
   int rank;
   hsize_t dims[4];
   unsigned long long n = 1;
   int i;
   if (file == NULL || path == NULL || buf == NULL || cap <= 0) {
      set_error("invalid text read");
      return -1;
   }
   buf[0] = '\0';
   dset = H5Dopen2(file->file, path, H5P_DEFAULT);
   if (dset < 0) {
      set_error("text dataset missing");
      return -1;
   }
   space = H5Dget_space(dset);
   type = H5Dget_type(dset);
   class_id = H5Tget_class(type);
   rank = H5Sget_simple_extent_ndims(space);
   if (rank < 0) {
      rank = 0;
   }
   if (rank > 4) {
      rank = 4;
   }
   if (rank > 0) {
      H5Sget_simple_extent_dims(space, dims, NULL);
      for (i = 0; i < rank; i++) {
         n *= (unsigned long long)dims[i];
      }
   }
   if (class_id == H5T_STRING) {
      if (H5Tis_variable_str(type) > 0) {
         char *value = NULL;
         if (H5Dread(dset, type, H5S_ALL, H5S_ALL, H5P_DEFAULT, &value) >= 0 && value != NULL) {
            snprintf(buf, (size_t)cap, "%s", value);
            H5free_memory(value);
         }
      } else {
         size_t size = H5Tget_size(type);
         char *raw = calloc(1, size + 1);
         if (raw != NULL && H5Dread(dset, type, H5S_ALL, H5S_ALL, H5P_DEFAULT, raw) >= 0) {
            raw[size] = '\0';
            snprintf(buf, (size_t)cap, "%s", raw);
         }
         free(raw);
      }
   } else if (class_id == H5T_INTEGER && H5Tget_size(type) == 1 && n >= 1 && n <= 4096) {
      int8_t *raw = malloc((size_t)n);
      if (raw != NULL && H5Dread(dset, H5T_NATIVE_INT8, H5S_ALL, H5S_ALL, H5P_DEFAULT, raw) >= 0 &&
          (n == 1 || mostly_text(raw, n))) {
         if (n == 1 && ((unsigned char)raw[0] < 32 || (unsigned char)raw[0] >= 127)) {
            snprintf(buf, (size_t)cap, "%d", (int)raw[0]);
         } else {
            unsigned long long k;
            int pos = 0;
            for (k = 0; k < n && pos + 1 < cap; k++) {
               char c = (char)raw[k];
               if (c == '\0') {
                  break;
               }
               buf[pos++] = c;
            }
            buf[pos] = '\0';
         }
      }
      free(raw);
   } else if (n == 1 && (class_id == H5T_INTEGER || class_id == H5T_FLOAT)) {
      double value = 0.0;
      if (H5Dread(dset, H5T_NATIVE_DOUBLE, H5S_ALL, H5S_ALL, H5P_DEFAULT, &value) >= 0) {
         snprintf(buf, (size_t)cap, "%.12g", value);
      }
   } else {
      H5Tclose(type);
      H5Sclose(space);
      H5Dclose(dset);
      set_error("dataset is not text");
      return -1;
   }
   H5Tclose(type);
   H5Sclose(space);
   H5Dclose(dset);
   return buf[0] == '\0' ? -1 : 0;
}

int meddb_h5_read_scalar(meddb_h5 *file, const char *path, double *out) {
   hid_t dset, space, type;
   H5T_class_t class_id;
   int rank;
   hsize_t dims[4];
   unsigned long long n = 1;
   int i;
   if (file == NULL || path == NULL || out == NULL) {
      set_error("invalid scalar read");
      return -1;
   }
   dset = H5Dopen2(file->file, path, H5P_DEFAULT);
   if (dset < 0) {
      set_error("scalar dataset missing");
      return -1;
   }
   space = H5Dget_space(dset);
   type = H5Dget_type(dset);
   class_id = H5Tget_class(type);
   rank = H5Sget_simple_extent_ndims(space);
   if (rank > 0 && rank <= 4) {
      H5Sget_simple_extent_dims(space, dims, NULL);
      for (i = 0; i < rank; i++) {
         n *= (unsigned long long)dims[i];
      }
   }
   if (n != 1 || (class_id != H5T_INTEGER && class_id != H5T_FLOAT)) {
      H5Tclose(type);
      H5Sclose(space);
      H5Dclose(dset);
      set_error("dataset is not a numeric scalar");
      return -1;
   }
   if (H5Dread(dset, H5T_NATIVE_DOUBLE, H5S_ALL, H5S_ALL, H5P_DEFAULT, out) < 0) {
      H5Tclose(type);
      H5Sclose(space);
      H5Dclose(dset);
      set_error("scalar read failed");
      return -1;
   }
   H5Tclose(type);
   H5Sclose(space);
   H5Dclose(dset);
   return 0;
}

int meddb_h5_read_waveform(meddb_h5 *file, const char *path,
                           unsigned long long start, unsigned long long count,
                           double **out, unsigned long long *n_channels,
                           unsigned long long *n_samples) {
   hid_t dset, space, memspace;
   int rank;
   hsize_t dims[2];
   hsize_t hstart[2];
   hsize_t hcount[2];
   unsigned long long d0;
   unsigned long long d1;
   int long_axis;
   unsigned long long nlong;
   unsigned long long nchan;
   unsigned long long nread;
   double *raw = NULL;
   double *packed = NULL;
   herr_t status;
   if (file == NULL || path == NULL || out == NULL) {
      set_error("invalid waveform read");
      return -1;
   }
   dset = H5Dopen2(file->file, path, H5P_DEFAULT);
   if (dset < 0) {
      set_error("waveform dataset missing");
      return -1;
   }
   space = H5Dget_space(dset);
   rank = H5Sget_simple_extent_ndims(space);
   if (rank != 1 && rank != 2) {
      H5Sclose(space);
      H5Dclose(dset);
      set_error("waveform rank must be 1 or 2");
      return -1;
   }
   dims[0] = 1;
   dims[1] = 1;
   H5Sget_simple_extent_dims(space, dims, NULL);
   d0 = (unsigned long long)dims[0];
   d1 = rank == 1 ? 1 : (unsigned long long)dims[1];
   long_axis = d0 >= d1 ? 0 : 1;
   nlong = long_axis == 0 ? d0 : d1;
   nchan = long_axis == 0 ? d1 : d0;
   if (nchan == 0 || nchan > 256) {
      H5Sclose(space);
      H5Dclose(dset);
      set_error("channel count is not a waveform");
      return -1;
   }
   if (start > nlong) {
      start = nlong;
   }
   nread = count;
   if (start + nread > nlong) {
      nread = nlong - start;
   }
   hstart[0] = 0;
   hstart[1] = 0;
   hcount[0] = (hsize_t)d0;
   hcount[1] = (hsize_t)d1;
   hstart[long_axis] = (hsize_t)start;
   hcount[long_axis] = (hsize_t)nread;
   if (H5Sselect_hyperslab(space, H5S_SELECT_SET, hstart, NULL, hcount, NULL) < 0) {
      H5Sclose(space);
      H5Dclose(dset);
      set_error("hyperslab selection failed");
      return -1;
   }
   memspace = H5Screate_simple(rank, hcount, NULL);
   raw = malloc((size_t)(nchan * (nread == 0 ? 1 : nread)) * sizeof(double));
   packed = malloc((size_t)(nchan * (nread == 0 ? 1 : nread)) * sizeof(double));
   if (raw == NULL || packed == NULL) {
      free(raw);
      free(packed);
      H5Sclose(memspace);
      H5Sclose(space);
      H5Dclose(dset);
      set_error("out of memory");
      return -1;
   }
   status = H5Dread(dset, H5T_NATIVE_DOUBLE, memspace, space, H5P_DEFAULT, raw);
   if (status < 0) {
      free(raw);
      free(packed);
      H5Sclose(memspace);
      H5Sclose(space);
      H5Dclose(dset);
      set_error("H5Dread failed");
      return -1;
   }
   if (rank == 1 || long_axis == 1) {
      memcpy(packed, raw, (size_t)(nchan * nread) * sizeof(double));
   } else {
      unsigned long long s, c;
      for (s = 0; s < nread; s++) {
         for (c = 0; c < nchan; c++) {
            packed[c * nread + s] = raw[s * nchan + c];
         }
      }
   }
   free(raw);
   H5Sclose(memspace);
   H5Sclose(space);
   H5Dclose(dset);
   *out = packed;
   if (n_channels) *n_channels = nchan;
   if (n_samples) *n_samples = nread;
   return 0;
}

void meddb_h5_free(void *ptr) {
   free(ptr);
}
