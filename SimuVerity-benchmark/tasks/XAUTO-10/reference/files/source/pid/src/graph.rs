use plotters::prelude::*;
use std::error::Error;

pub fn yaw(current: Vec<f32>, desired: Vec<f32>) -> Result<(), Box<dyn Error>>
{
    const OUT_FILE_NAME: &str = "yawrates.png";
    let root = BitMapBackend::new(OUT_FILE_NAME, (1024, 768)).into_drawing_area();
    root.fill(&WHITE)?;

    let cur_min = bounds(current.clone(), true);
    let des_min = bounds(desired.clone(), true);
    let cur_max = bounds(current.clone(), false);
    let des_max = bounds(desired.clone(), false);
    let cur_len = current.len() - 1;
    let des_len = desired.len() - 1;

    let min: f32 = min_bounds(cur_min, des_min);
    let max: f32 = max_bounds(cur_max, des_max);
    let time: f32 = max_bounds(cur_len as f32, des_len as f32);

    let mut chart = ChartBuilder::on(&root)
        .x_label_area_size(35)
        .y_label_area_size(45)
        .margin(5)
        .caption("Yaw Rates", ("sans-serif", 50.0).into_font())
        .build_cartesian_2d(0f32..time, min..max)?
        .set_secondary_coord(0f32..time, min..max);

    chart
        .configure_mesh()
        .disable_x_mesh()
        .disable_y_mesh()
        .x_desc("Time (microseconds)")
        .y_desc("Yaw Rate (radians/s)")
        .draw()?;

    chart
        .draw_series(LineSeries::new((0 ..= cur_len)
        .map(|x| (x as f32, current[x])), BLUE,))?
        .label("Actual Yaw Rate")
        .legend(|(x, y)| PathElement::new(vec![(x, y), (x + 20, y)], BLUE));

    chart
        .draw_secondary_series(LineSeries::new((0 ..= des_len)
        .map(|x| (x as f32, desired[x])), RED,))?
        .label("Desired Yaw Rate")
        .legend(|(x, y)| PathElement::new(vec![(x, y), (x + 20, y)], RED));

    chart
        .configure_series_labels()
        .background_style(RGBColor(128, 128, 128))
        .draw()?;

    // To avoid the IO failure being ignored silently, we manually call the present function
    root.present().expect("Unable to write result to file");
    println!("Result has been saved to {}", OUT_FILE_NAME);

    Ok(())
}

pub fn velocity(vehicle: Vec<f32>, wheel: Vec<f32>, horizontal: Vec<f32>, slippage: Vec<f32>) -> Result<(), Box<dyn std::error::Error>> 
{
    const OUT_FILE_NAME: &str = "velocities.png";
    let root = BitMapBackend::new(OUT_FILE_NAME, (1024, 768)).into_drawing_area();
    root.fill(&WHITE)?;

    let vmin = bounds(vehicle.clone(), true);
    let wmin = bounds(wheel.clone(), true);
    let hmin = bounds(horizontal.clone(), true);
    let smin = bounds(slippage.clone(), true);
    let vmax = bounds(vehicle.clone(), false);
    let wmax = bounds(wheel.clone(), false);
    let hmax = bounds(horizontal.clone(), false);
    let smax = bounds(slippage.clone(), false);
    let vlen = vehicle.len() - 1;
    let wlen = wheel.len() - 1;
    let hlen = horizontal.len() - 1;
    let slen = slippage.len() - 1;

    let mina: f32 = min_bounds(vmin, wmin);
    let minb: f32 = min_bounds(hmin, smin);
    let min: f32 = min_bounds(mina, minb);

    let maxa: f32 = max_bounds(vmax, wmax);
    let maxb: f32 = max_bounds(hmax, smax);
    let max: f32 = max_bounds(maxa, maxb);

    let timea: f32 = max_bounds(vlen as f32, wlen as f32);
    let timeb: f32 = max_bounds(hlen as f32, slen as f32);
    let time: f32 = max_bounds(timea, timeb);

    let mut chart = ChartBuilder::on(&root)
        .x_label_area_size(35)
        .y_label_area_size(45)
        .right_y_label_area_size(50)
        .margin(5)
        .caption("Velocities n' Slippage", ("sans-serif", 50.0).into_font())
        .build_cartesian_2d(0f32..time, min..max)?
        .set_secondary_coord(0f32..time, min..max);

    chart
        .configure_mesh()
        .disable_x_mesh()
        .disable_y_mesh()
        .x_desc("Time (microseconds)")
        .y_desc("Velocity (m/s)")
        .draw()?;

    chart
        .configure_secondary_axes()
        .y_desc("Slippage (%)")
        .draw()?;

    chart
        .draw_series(LineSeries::new((0 ..= vlen)
        .map(|x| (x as f32, vehicle[x])), GREEN,))?
        .label("Vehicle Velocity")
        .legend(|(x, y)| PathElement::new(vec![(x, y), (x + 20, y)], GREEN));

    chart
        .draw_secondary_series(LineSeries::new((0 ..= wlen)
        .map(|x| (x as f32, wheel[x])), BLUE,))?
        .label("Wheel Velocity")
        .legend(|(x, y)| PathElement::new(vec![(x, y), (x + 20, y)], BLUE));
    
    chart
        .draw_secondary_series(LineSeries::new((0 ..= hlen)
        .map(|x| (x as f32, horizontal[x])), MAGENTA,))?
        .label("Horizontal Velocity")
        .legend(|(x, y)| PathElement::new(vec![(x, y), (x + 20, y)], MAGENTA));
    
    chart
        .draw_secondary_series(LineSeries::new((0 ..= slen)
        .map(|x| (x as f32, slippage[x])), RED,))?
        .label("Slippage")
        .legend(|(x, y)| PathElement::new(vec![(x, y), (x + 20, y)], RED));

    chart
        .configure_series_labels()
        .background_style(RGBColor(128, 128, 128))
        .draw()?;

    // To avoid the IO failure being ignored silently, we manually call the present function
    root.present().expect("Unable to write result to file, please make sure 'plotters-doc-data' dir exists under current dir");
    println!("Result has been saved to {}", OUT_FILE_NAME);

    Ok(())
}

fn min_bounds(cur: f32, des: f32) -> f32
{
    // determine minimum value for graph bounds
    if cur < des 
    { 
        cur
    }
    else 
    { 
        des
    }
}

fn max_bounds(cur: f32, des: f32) -> f32
{
    // determine maximum value for graph bounds
    if cur > des 
    { 
        cur
    }
    else 
    { 
        des
    }
}

fn bounds(v: Vec<f32>, min: bool) -> f32
{
    // language doesn't seem to have a built-in solution for this with f32 vectors
    let mut val: f32 = v[0];

    if min
    {
        for i in &v
        {
            if val > *i
            {
                val = *i
            }
        }
    }
    else
    {
        for i in &v
        {
            if val < *i
            {
                val = *i
            }
        }
    }
    val
}
