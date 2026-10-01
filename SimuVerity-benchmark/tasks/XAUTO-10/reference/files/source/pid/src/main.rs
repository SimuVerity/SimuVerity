mod calc;
mod graph;
mod export;
use std::env;
use std::io;
use std::io::Write;
use prompted::input;

fn main() -> Result<(), Box<dyn std::error::Error>>
{
    let args: Vec<_> = env::args().collect(); //collecting arguments
    let a_x: Vec<f32>;
    let a_y: Vec<f32>;
    let wheel_velocity: Vec<f32>;
    let curr_yaw_rate: Vec<f32>;
    let des_yaw_rate: Vec<f32>;

    if args.len() <= 4 || args.len() > 5 
    { 
        //Not enough arguments or too little provided
        println!("Error, not enough arguments provided or too many");
        println!("usage: cargo run <starting velocity (m/s)> <left wheel torque (Nm)> <right wheel torque (Nm)> <steering angle (degrees)>");
        println!("Example: cargo run 1 5 5 20");
        return Ok(());
    }

    let starting_vel: f32 = args[1].parse().unwrap();
    let l_torque: f32 = args[2].parse().unwrap();
    let r_torque: f32 = args[3].parse().unwrap();
    let st_angle: f32 = args[4].parse().unwrap();

    (a_x, a_y, wheel_velocity, curr_yaw_rate, des_yaw_rate) = calc::simulate(starting_vel, starting_vel, l_torque, r_torque, st_angle);

    let mut i = 1;
    let mut total_slip: Vec<f32> = Vec::new();
    total_slip.push(((wheel_velocity[i] / a_x[i]) - 1.0) * 100.0);

    while i < a_x.len() 
    {
        total_slip.push(((wheel_velocity[i] / a_x[i]) - 1.0) * 100.0);
        i += 1;
    }

    let _yaw = graph::yaw(curr_yaw_rate.clone(), des_yaw_rate.clone());
    let _vel = graph::velocity(a_x.clone(), wheel_velocity.clone(), a_y.clone(), total_slip.clone());

    print!("Do you want to print results out to a CSV file? (1 for yes, 0 for no): ");
    io::stdout().flush().unwrap();
    let user_in: String = input!();
    let user_in2: i32 = user_in.parse().unwrap();
    if user_in2 == 1 
    {
        let _csv = export::csv(curr_yaw_rate, des_yaw_rate, a_x, wheel_velocity, a_y, total_slip);
        println!(" EXPORTED CSV FILES ");
    }
 
    Ok(()) 
}
