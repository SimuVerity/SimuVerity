#include "comm.h"

adc_buffer  adc_buf1 = { .top=0, .count=0 },
            adc_buf2 = { .top=0, .count=0 },
            adc_buf3 = { .top=0, .count=0 };
throttle_in_buffer throttle_buf = { .top=0, .count=0 };
steering_angle_buffer steering_angle_buf = { .top=0, .count=0 };
throttle_percents throttle_out;

uint16_t push_adc_buf(adc_buffer *buf, uint16_t val)
{
  buf->buf[buf->top] = val;
  buf->top = (1 + buf->top) % ADC_BUF_LEN;
  if (buf->count < ADC_BUF_LEN)
    ++buf->count;

  return val;
}

float push_throttle_in_buf(throttle_in_buffer *buf, float val)
{
  buf->buf[buf->top] = val;
  buf->top = (1 + buf->top) % ADC_BUF_LEN;
  if (buf->count < ADC_BUF_LEN)
    ++buf->count;

  return val;
}

float push_steering_angle_buf(steering_angle_buffer *buf, float val)
{
  buf->buf[buf->top] = val;
  buf->top = (1 + buf->top) % ADC_BUF_LEN;
  if (buf->count < ADC_BUF_LEN)
    ++buf->count;

  return val;
}

throttle_percents write_throttle_out(throttle_percents val, DAC_HandleTypeDef hdac)
{
  float sum;
  uint16_t left, right;

  sum = val.left + val.right;
  if (sum > MAX_THROTTLE_PERCENT)
  {
    val.left  = val.left  / sum * MAX_THROTTLE_PERCENT;
    val.right = val.right / sum * MAX_THROTTLE_PERCENT;
  }

  left  = (uint16_t)(4095.0 * val.left  / 100.0);
  right = (uint16_t)(4095.0 * val.right / 100.0);


  if (HAL_DAC_SetValue(&hdac, DAC_CHANNEL_1, DAC_ALIGN_12B_R, left) != HAL_OK)
  {
    //Error_Handler();
  }

  if (HAL_DAC_SetValue(&hdac, DAC_CHANNEL_2, DAC_ALIGN_12B_R, right) != HAL_OK)
  {
    //Error_Handler();
  }

  return val;
}

float get_throttle_in_smooth(void)
{
  int num_samples, i, first;
  num_samples = SMOOTH_NUM_SAMPLES;

  if (num_samples > throttle_buf.count)
    num_samples = throttle_buf.count;
  
  first = throttle_buf.top + ADC_BUF_LEN - num_samples;

  float sum = 0.0f;
  for (i = 0; i < num_samples; ++i)
  {
    sum += throttle_buf.buf[(first + i)%ADC_BUF_LEN];
  }

  return sum/num_samples;
}

float get_steering_angle_smooth(void)
{
  int num_samples, i, first;
  num_samples = SMOOTH_NUM_SAMPLES;

  if (num_samples > steering_angle_buf.count)
    num_samples = steering_angle_buf.count;
  
  first = steering_angle_buf.top + ADC_BUF_LEN - num_samples;

  float sum = 0.0f;
  for (i = 0; i < num_samples; ++i)
  {
    sum += steering_angle_buf.buf[(first + i)%ADC_BUF_LEN];
  }

  return sum/num_samples;
}

