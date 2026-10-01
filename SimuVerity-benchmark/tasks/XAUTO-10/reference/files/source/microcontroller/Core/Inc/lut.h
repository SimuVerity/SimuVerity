#ifndef __LUT_H
#define __LUT_H

#include <stdint.h>
#include "calc.h"

// In: Steering angle, throttle %
// Out: Left, Right (sum: 100%)

typedef struct {
  uint16_t i; // Steering Angle
  uint16_t j; // Car Velocity
} LUT_index;

typedef struct {
  float i; // Steering Angle
  float j; // Car Velocity
} LUT_index_float;

typedef struct {
  LUT_index top_left;
  LUT_index top_right;
  LUT_index bottom_left;
  LUT_index bottom_right;
  LUT_index_float ref;
} LUT_index_quad;

#define STEERING_ANGLE_RESOLUTION 17
#define VELOCITY_RESOLUTION 17

extern throttle_percents LUT[STEERING_ANGLE_RESOLUTION][VELOCITY_RESOLUTION];

throttle_percents LUT_lookup(LUT_index in);

LUT_index nearest_index(float steering_angle, float velocity);
LUT_index_float index_float(float steering_angle, float velocity);
LUT_index_quad interp_indices(float steering_angle, float velocity);

throttle_percents lookup_nearest(float steering_angle, float velocity);
throttle_percents lookup_linear(float steering_angle, float velocity);

#endif
