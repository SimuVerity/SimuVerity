use pid::graph;

#[test]
fn test_yaw()
{ 
    let mut cur: Vec<f32> = Vec::new();
    cur.push(1_f32);
    cur.push(2_f32);

    let mut des: Vec<f32> = Vec::new();
    des.push(4_f32);
    des.push(5_f32);

    let _ = graph::yaw(cur, des);
}

#[test]
fn test_velocity()
{
    let mut v: Vec<f32> = Vec::new();
    v.push(1_f32);
    v.push(2_f32);

    let mut w: Vec<f32> = Vec::new();
    w.push(4_f32);
    w.push(5_f32);

    let mut h: Vec<f32> = Vec::new();
    h.push(6_f32);
    h.push(7_f32);

    let mut s: Vec<f32> = Vec::new();
    s.push(8_f32);
    s.push(9_f32);
    
    let _ = graph::velocity(v, w, h, s);
}
