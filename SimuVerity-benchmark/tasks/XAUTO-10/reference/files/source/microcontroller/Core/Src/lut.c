#include "lut.h"

#define MIN_STEERING_ANGLE (-0.6356685485304198)   // constant: -230deg => steering angle
#define MAX_STEERING_ANGLE   0.6345749252211202   // constant:  230deg => steering angle
#define MIN_VELOCITY 0.5
#define MAX_VELOCITY 40

throttle_percents LUT[STEERING_ANGLE_RESOLUTION][VELOCITY_RESOLUTION] =
#include "table.dat"

throttle_percents LUT_lookup(LUT_index in)
{
  return LUT[in.i][in.j];
}

LUT_index nearest_index(float steering_angle, float velocity)
{
  LUT_index_float ref, shifted;

  ref = index_float(steering_angle, velocity);
  shifted = (LUT_index_float){
    .i = ref.i + 0.5,
    .j = ref.j + 0.5,
  };

  return (LUT_index){
    .i = (uint16_t)shifted.i,
    .j = (uint16_t)shifted.j,
  };
}

LUT_index_float index_float(float steering_angle, float velocity)
{
  float i, j;

  i = steering_angle;                           // [min, max)
  i -= MIN_STEERING_ANGLE;                      // [0, max - min)
  i /= MAX_STEERING_ANGLE - MIN_STEERING_ANGLE; // [0, 1)
  i *= STEERING_ANGLE_RESOLUTION;               // [0, res)

  j = velocity;                                 // [min, max]
  j -= MIN_VELOCITY;                            // [0, max - min]
  j /= MAX_VELOCITY - MIN_VELOCITY;             // [0, 1]
  j *= VELOCITY_RESOLUTION;                     // [0, res]

  return (LUT_index_float){
    .i = i,
    .j = j,
  };
}

LUT_index_quad interp_indices(float steering_angle, float velocity)
{
  LUT_index_float ref;
  LUT_index top_left;
  int dx, dy;

  dx = dy = 1;

  ref = index_float(steering_angle, velocity);
  top_left = (LUT_index){
    .i = (uint16_t)ref.i,
    .j = (uint16_t)ref.j,
  };

  if (top_left.i == STEERING_ANGLE_RESOLUTION)
    dx = 0;

  if (top_left.j == VELOCITY_RESOLUTION)
    dy = 0;

  return (LUT_index_quad){
    .top_left     = top_left,
    .top_right    = { top_left.i + dx, top_left.j,      },
    .bottom_left  = { top_left.i,      top_left.j + dy, },
    .bottom_right = { top_left.i + dx, top_left.j + dy, },
    .ref = ref,
  };
}

throttle_percents lookup_nearest(float steering_angle, float velocity)
{
  LUT_index in = nearest_index(steering_angle, velocity);
  return LUT_lookup(in);
}

// Private
float lerp(float a, float b, float t)
{
  return a*(1-t) + b*t;
}

throttle_percents lookup_linear(float steering_angle, float velocity)
{
  LUT_index_quad in;
  throttle_percents top_left, top_right, bottom_left, bottom_right,
                    top, bottom;
  float s, t;
  in = interp_indices(steering_angle, velocity);
  s = in.ref.i - in.top_left.i;
  t = in.ref.j - in.top_left.j;

  top_left      = LUT_lookup(in.top_left);
  top_right     = LUT_lookup(in.top_right);
  bottom_left   = LUT_lookup(in.bottom_left);
  bottom_right  = LUT_lookup(in.bottom_right);

  top = (throttle_percents){
    .left  = lerp(top_left.left,  top_right.left,  s),
    .right = lerp(top_left.right, top_right.right, s),
  };

  bottom = (throttle_percents){
    .left  = lerp(bottom_left.left,  bottom_right.left,  s),
    .right = lerp(bottom_left.right, bottom_right.right, s),
  };

  return (throttle_percents){
    .left  = lerp(top.left,  bottom.left,  t),
    .right = lerp(top.right, bottom.right, t),
  };
}

