use csv::Writer;
use std::fs;
use std::error::Error;
use std::path::MAIN_SEPARATOR;

pub fn csv(current_yaw: Vec<f32>, desired_yaw: Vec<f32>, vehicle: Vec<f32>, wheel: Vec<f32>, horizontal: Vec<f32>, slippage: Vec<f32>) 
    -> Result<(), Box<dyn Error>>
{
    let path = "csv".to_owned() + &MAIN_SEPARATOR.to_string();
    let _dir = fs::create_dir(&path);

    let c = Writer::from_path(format!("{}{}", path, "current_yaw.csv"))?;
    let d = Writer::from_path(format!("{}{}", path, "desired_yaw.csv"))?;  

    let v = Writer::from_path(format!("{}{}", path, "vehicle_velocity.csv"))?;
    let w = Writer::from_path(format!("{}{}", path, "wheel_velocity.csv"))?;
    let h = Writer::from_path(format!("{}{}", path, "horizontal_velocity.csv"))?;
    let s = Writer::from_path(format!("{}{}", path, "slippage_velocity.csv"))?;

    convert(current_yaw, c);
    convert(desired_yaw, d);

    convert(vehicle, v);
    convert(wheel, w);
    convert(horizontal, h);
    convert(slippage, s);

    Ok(())
}

fn convert<W: std::io::Write>(v: Vec<f32>, mut w: Writer<W>)
{
    for i in &v
    {
        let _ = w.write_field(i.to_string());
    }
    let _toilet = w.flush();
}
