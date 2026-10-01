#ifndef __COMM_H
#define __COMM_H

#include <stdlib.h>
#include "stm32f4xx_hal.h"
#include "calc.h"

#define ADC_BUF_LEN 3
#define SMOOTH_NUM_SAMPLES 3

typedef struct {
  uint16_t buf[ADC_BUF_LEN];
  size_t top;
  size_t count;
} adc_buffer;

typedef struct {
  float buf[ADC_BUF_LEN];
  size_t top;
  size_t count;
} throttle_in_buffer;

typedef struct {
  float buf[ADC_BUF_LEN];
  size_t top;
  size_t count;
} steering_angle_buffer;

extern adc_buffer adc_buf1, adc_buf2, adc_buf3;
extern throttle_in_buffer throttle_buf;
extern steering_angle_buffer steering_angle_buf;
extern throttle_percents throttle_out;

uint16_t push_adc_buf(adc_buffer *buf, uint16_t val);
float push_throttle_in_buf(throttle_in_buffer *buf, float val);
float push_steering_angle_buf(steering_angle_buffer *buf, float val);
throttle_percents write_throttle_out(throttle_percents val, DAC_HandleTypeDef hdac);

float get_throttle_in_smooth(void);
float get_steering_angle_smooth(void);

#endif
