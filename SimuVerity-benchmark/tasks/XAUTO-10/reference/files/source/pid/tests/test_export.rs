use pid::export;

#[test]
fn test_csv()
{
    let mut c: Vec<f32> = Vec::new();
    c.push(1_f32);
    c.push(2_f32);

    let mut d: Vec<f32> = Vec::new();
    d.push(4_f32);
    d.push(5_f32);

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

    let _ = export::csv(c, d, v, w, h, s);
}
