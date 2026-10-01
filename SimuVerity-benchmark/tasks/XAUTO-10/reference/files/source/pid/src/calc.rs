// Calculations based on Torque Vectoring for a Formula Student Prototype, Dissertacao
// Constants based on car characteristics from the 2023 Viking Motorsports car

use std::f32::consts;

// PID Parameters
pub const POR: f32 = 1000.0;
pub const INT: f32 = 40.0;
pub const DER: f32 = 0.0;

// Gear ratio
pub const GR: f32 = 4.1;

// Wheel radius in meters
pub const WHEEL_RADIUS: f32 = 0.4;

// Inertia Moment around z axis
pub const IZZ: f32 = 120.0;

// Half track of rear axle in meters
pub const TR: f32 = 0.6604;

// Radius of wheel
pub const RW: f32 = 0.2286;

// lf (float): Distance between the center of gravity and the front axle in meters
pub const LF: f32 = 0.885;

// lr (float): Distance between the center of gravity and the rear axle in meters
pub const LR: f32 = 0.770;

// m (float): Mass of the vehicle in kilograms
pub const M: f32 = 222.26;

// Cy_f (float): Cornering stiffness of the front tires in N/rad
pub const CY_F: f32 = 7085.0;

// Cy_r (float): Cornering stiffness of the rear tires in N/rad
pub const CY_R: f32 = 7302.0;

// Weight of car multiplied by gravity
pub const WEIGHT: f32 = M * 9.81;

// Constants for magic formula tire model
pub const B: f32 = 10.0;
pub const C: f32 = 1.9;
pub const D: f32 = 1.0; 
pub const E: f32 = 0.97;

pub fn p(error: f32) -> f32 
{
    let val: f32 = POR * error;
    val
}

pub fn i(error: f32, time: f32) -> f32 
{
    let val: f32 = INT * error * time;
    val
}

pub fn d(error: f32, time: f32, prev_error: f32) -> f32 
{
    if time == 0.0 {
        return 0.0;
    }
    let val: f32 = DER * (error * prev_error) / time;
    val
}

pub fn radians_to_ms(radians: f32) -> f32 
{
    radians * WHEEL_RADIUS
}

pub fn degrees_to_radians(degrees: f32) -> f32 
{
    degrees * (consts::PI / 180.0)
}

pub fn calculate_desired_yaw_rate(v_cg: f32, delta: f32) -> f32 
{
    let des_yaw_rate: f32 = (v_cg / ((LF + LR) + (0.0012965 * v_cg.powf(2.0)))) * delta;
    des_yaw_rate
}

pub fn calculate_yaw_rate(t: f32, mut ku: f32, vx: f32, st_a: f32, trr: f32, trl: f32) -> f32 
{
    if t > 20.0 && vx > 2.0 { //Starting at velocity 1.8 because the jerk (change in acceleration) calculation causes inconsistencies before that velocity.
        ku += ((((-LF * CY_F + LR * CY_R) / (IZZ * vx)) - ((LF.powf(2.0) * CY_F + LR.powf(2.0) * CY_R) / (IZZ * vx))) * ku + ((LF * CY_F) / IZZ) * st_a + (1.0 / (0.05 * IZZ)) * calculate_delta_torque(trr, trl)) / t;
    }
    ku
}

pub fn calculate_yaw_moment(trr: f32, trl: f32) -> f32 
{
    let m_v: f32 = (trr - trl) * TR;
    m_v
}

pub fn calculate_lateral_velocity(vx: f32, st_a: f32) -> f32 
{
    let vy: f32 = ((-(CY_F + CY_R)/(M * vx)) + (((-LF * CY_F + LR + CY_R)/(M * vx)) - vx)) + (CY_F / (M * vx)) * st_a;
    vy
}

pub fn calculate_delta_torque(trr: f32, trl: f32) -> f32 
{
    let delt_t: f32 = (RW / (2.0 * TR * GR)) * calculate_yaw_moment(trr, trl);
    delt_t
}

pub fn magic_formula(w: f32, mut p: f32) -> f32 
{

    p -= 1.0;
    let f: f32 = w * D * f32::sin(C * f32::atan(B * p * (1.0 - E) + E * B * p - f32::atan(B * p)));
    f
}

pub fn steering_wheel_angle_to_steering_angle(steering_wheel_angle: f32) -> f32 
{
    let mut x: f32;
    if steering_wheel_angle >= 0.0
    {
        x = 8.355 * 10_f32.powf(-5.0) * (steering_wheel_angle.powi(2)) + 0.139 * steering_wheel_angle - 0.03133;
    } else {
        x = 8.355 * 10_f32.powf(-5.0) * (-steering_wheel_angle.powi(2)) + 0.139 * steering_wheel_angle - 0.03133;
    }
    x = degrees_to_radians(x);
    x
}

pub fn calculate_power_ratio(error: f32, prev_error: f32, time: f32, max_torque: f32) -> (f32, f32) 
{
    let mut ratio: f32 = p(error) + i(error, time) + d(error, time, prev_error);
    ratio = ratio.max(0.0).min(100.0);
    if ratio > 0.0 {
        ratio /= 100.0;
    }
    
    let rl_torque_wheel: f32 = ratio * max_torque;
    let rr_torque_wheel: f32 = (1.0 - ratio) * max_torque;
    (rl_torque_wheel, rr_torque_wheel)
}

type Info = (Vec<f32>, Vec<f32>, Vec<f32>, Vec<f32>, Vec<f32>);

pub fn simulate(mut v_cg: f32, w_velocity: f32, mut rl_torque_wheel: f32, mut rr_torque_wheel: f32, mut steering_a: f32) -> Info
{
    steering_a = steering_wheel_angle_to_steering_angle(steering_a);
    let mut a_x: Vec<f32> = Vec::new();
    a_x.push(v_cg);
    let mut a_y: Vec<f32> = Vec::new();
    a_y.push(0.0);
    let mut wheel_velocity: Vec<f32> = Vec::new();
    wheel_velocity.push(w_velocity);
    let mut curr_yaw_rate: Vec<f32> = Vec::new();
    curr_yaw_rate.push(0.0);
    let mut des_yaw_rate: Vec<f32> = Vec::new();
    des_yaw_rate.push(calculate_desired_yaw_rate(v_cg, steering_a));

    let mut rl_wheel_angular_accel: f32;
    let mut rr_wheel_angular_accel: f32;
    let mut rl_wheel_angular_v: f32;
    let mut rr_wheel_angular_v: f32;
    let mut rl_slippage: f32;
    let mut rr_slippage: f32;
    let mut f: f32;
    let mut long_accel: f32;
    let mut error: f32 = 0.0;
    let mut prev_error: f32;
    let max_torque: f32 = rr_torque_wheel + rl_torque_wheel;

    for i in 0..10000 
    {
        rl_wheel_angular_accel = radians_to_ms((2.0 *rl_torque_wheel) / (9.0  * WHEEL_RADIUS));
        rr_wheel_angular_accel = radians_to_ms((2.0 *rr_torque_wheel) / (9.0  * WHEEL_RADIUS));
        prev_error = error;
        rl_slippage = (v_cg + rl_wheel_angular_accel) / v_cg;
        rr_slippage = (v_cg + rr_wheel_angular_accel) / v_cg;
        if rl_slippage < 1.0 
        {
            rl_slippage = 1.0;
        }
        if rr_slippage < 1.0 
        {
            rr_slippage = 1.0;
        }
        f = magic_formula(WEIGHT / 2.0, (rl_slippage + rr_slippage) / 2.0);
        long_accel = (f / M) / 100.0;
        v_cg += long_accel;
        rl_wheel_angular_v = rl_slippage * v_cg;
        rr_wheel_angular_v = rr_slippage * v_cg;
        error = (curr_yaw_rate[i] - des_yaw_rate[i]) / des_yaw_rate[i].abs();
        (rl_torque_wheel, rr_torque_wheel) = calculate_power_ratio(error, prev_error, i as f32, max_torque);
        a_x.push(a_x[i] + long_accel);
        wheel_velocity.push((rl_wheel_angular_v + rr_wheel_angular_v) / 2.0);
        a_y.push(calculate_lateral_velocity(v_cg, steering_a));
        curr_yaw_rate.push(calculate_yaw_rate(i as f32, curr_yaw_rate[i], v_cg, steering_a, rr_torque_wheel, rl_torque_wheel));
        des_yaw_rate.push(calculate_desired_yaw_rate(v_cg, steering_a));
    }
    (a_x, a_y, wheel_velocity, curr_yaw_rate, des_yaw_rate)
    // return vector
}