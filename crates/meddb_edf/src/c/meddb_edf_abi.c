#include "meddb_edf_abi.h"

#include <edflib.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct meddb_edf {
   int handle;
   edflib_hdr_t *hdr;
};

static char last_error[512];

static void set_error(const char *text) {
   snprintf(last_error, sizeof last_error, "%s", text);
}

const char *meddb_edf_last_error(void) {
   return last_error;
}

static int bad_index(const meddb_edf *file, int index) {
   return file == NULL || file->hdr == NULL || index < 0 || index >= file->hdr->edfsignals;
}

int meddb_edf_open(const char *path, int read_annotations, meddb_edf **out) {
   meddb_edf *file;
   int rc;
   int mode = read_annotations ? EDFLIB_READ_ALL_ANNOTATIONS : EDFLIB_DO_NOT_READ_ANNOTATIONS;
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
   file->hdr = calloc(1, sizeof *file->hdr);
   if (file->hdr == NULL) {
      free(file);
      set_error("out of memory");
      return -1;
   }
   file->handle = -1;
   rc = edfopen_file_readonly(path, file->hdr, mode);
   if (rc != 0) {
      snprintf(last_error, sizeof last_error, "edflib open failed (%d)", file->hdr->filetype);
      free(file->hdr);
      free(file);
      return -1;
   }
   file->handle = file->hdr->handle;
   *out = file;
   last_error[0] = '\0';
   return 0;
}

void meddb_edf_close(meddb_edf *file) {
   if (file == NULL) {
      return;
   }
   if (file->handle >= 0) {
      edfclose_file(file->handle);
   }
   free(file->hdr);
   free(file);
}

int meddb_edf_filetype(const meddb_edf *file) {
   return file && file->hdr ? file->hdr->filetype : -1;
}

double meddb_edf_duration(const meddb_edf *file) {
   if (file == NULL || file->hdr == NULL) {
      return 0.0;
   }
   return (double)file->hdr->file_duration / (double)EDFLIB_TIME_DIMENSION;
}

double meddb_edf_record_duration(const meddb_edf *file) {
   if (file == NULL || file->hdr == NULL) {
      return 0.0;
   }
   return (double)file->hdr->datarecord_duration / (double)EDFLIB_TIME_DIMENSION;
}

int meddb_edf_nsignals(const meddb_edf *file) {
   return file && file->hdr ? file->hdr->edfsignals : 0;
}

long long meddb_edf_nannotations(const meddb_edf *file) {
   return file && file->hdr ? file->hdr->annotations_in_file : 0;
}

void meddb_edf_start(const meddb_edf *file, int *year, int *month, int *day,
                     int *hour, int *minute, int *second, double *subsecond) {
   if (year) *year = file && file->hdr ? file->hdr->startdate_year : 0;
   if (month) *month = file && file->hdr ? file->hdr->startdate_month : 0;
   if (day) *day = file && file->hdr ? file->hdr->startdate_day : 0;
   if (hour) *hour = file && file->hdr ? file->hdr->starttime_hour : 0;
   if (minute) *minute = file && file->hdr ? file->hdr->starttime_minute : 0;
   if (second) *second = file && file->hdr ? file->hdr->starttime_second : 0;
   if (subsecond) {
      *subsecond = file && file->hdr
         ? (double)file->hdr->starttime_subsecond / (double)EDFLIB_TIME_DIMENSION
         : 0.0;
   }
}

const char *meddb_edf_patient(const meddb_edf *file) {
   if (file == NULL || file->hdr == NULL) {
      return "";
   }
   if (file->hdr->patient_name[0] != '\0') {
      return file->hdr->patient_name;
   }
   if (file->hdr->patientcode[0] != '\0') {
      return file->hdr->patientcode;
   }
   return file->hdr->patient;
}

const char *meddb_edf_recording(const meddb_edf *file) {
   if (file == NULL || file->hdr == NULL) {
      return "";
   }
   if (file->hdr->recording_additional[0] != '\0') {
      return file->hdr->recording_additional;
   }
   return file->hdr->recording;
}

const char *meddb_edf_equipment(const meddb_edf *file) {
   return file && file->hdr ? file->hdr->equipment : "";
}

const char *meddb_edf_label(const meddb_edf *file, int index) {
   return bad_index(file, index) ? "" : file->hdr->signalparam[index].label;
}

const char *meddb_edf_units(const meddb_edf *file, int index) {
   return bad_index(file, index) ? "" : file->hdr->signalparam[index].physdimension;
}

const char *meddb_edf_transducer(const meddb_edf *file, int index) {
   return bad_index(file, index) ? "" : file->hdr->signalparam[index].transducer;
}

const char *meddb_edf_prefilter(const meddb_edf *file, int index) {
   return bad_index(file, index) ? "" : file->hdr->signalparam[index].prefilter;
}

double meddb_edf_fs(const meddb_edf *file, int index) {
   if (bad_index(file, index) || file->hdr->datarecord_duration <= 0) {
      return 0.0;
   }
   return (double)file->hdr->signalparam[index].smp_in_datarecord *
      (double)EDFLIB_TIME_DIMENSION / (double)file->hdr->datarecord_duration;
}

double meddb_edf_phys_min(const meddb_edf *file, int index) {
   return bad_index(file, index) ? 0.0 : file->hdr->signalparam[index].phys_min;
}

double meddb_edf_phys_max(const meddb_edf *file, int index) {
   return bad_index(file, index) ? 0.0 : file->hdr->signalparam[index].phys_max;
}

int meddb_edf_dig_min(const meddb_edf *file, int index) {
   return bad_index(file, index) ? 0 : file->hdr->signalparam[index].dig_min;
}

int meddb_edf_dig_max(const meddb_edf *file, int index) {
   return bad_index(file, index) ? 0 : file->hdr->signalparam[index].dig_max;
}

long long meddb_edf_nsamples(const meddb_edf *file, int index) {
   return bad_index(file, index) ? 0 : file->hdr->signalparam[index].smp_in_file;
}

int meddb_edf_read(meddb_edf *file, int index, long long start, int count, double *buf) {
   long long pos;
   int got;
   if (bad_index(file, index) || buf == NULL || count < 0) {
      set_error("invalid sample read");
      return -1;
   }
   if (count == 0) {
      return 0;
   }
   pos = edfseek(file->handle, index, start, EDFSEEK_SET);
   if (pos < 0) {
      set_error("edfseek failed");
      return -1;
   }
   got = edfread_physical_samples(file->handle, index, count, buf);
   if (got < 0) {
      set_error("edfread_physical_samples failed");
      return -1;
   }
   return got;
}

int meddb_edf_annotation(meddb_edf *file, long long index, double *onset_s,
                         double *duration_s, char *text, int text_cap) {
   edflib_annotation_t ann;
   if (file == NULL || file->hdr == NULL || index < 0 || text == NULL || text_cap <= 0) {
      set_error("invalid annotation read");
      return -1;
   }
   if (index > 2147483647LL) {
      set_error("annotation index is too large");
      return -1;
   }
   memset(&ann, 0, sizeof ann);
   if (edf_get_annotation(file->handle, (int)index, &ann) != 0) {
      set_error("edf_get_annotation failed");
      return -1;
   }
   if (onset_s) {
      *onset_s = (double)ann.onset / (double)EDFLIB_TIME_DIMENSION;
   }
   if (duration_s) {
      *duration_s = ann.duration_l < 0
         ? 0.0
         : (double)ann.duration_l / (double)EDFLIB_TIME_DIMENSION;
   }
   snprintf(text, (size_t)text_cap, "%s", ann.annotation);
   return 0;
}
