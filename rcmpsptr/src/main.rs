mod cmpsptr;

use std::mem::size_of;

use cmpsptr::cmpsptr::{CmpsRef, CmpsUnq, CmpsCnt};


struct Test {
    x: i32,
    y: i32
}

fn main() {
    let mut t = Test {x: 5, y: 9 };
    let mut z = Test {x: -3, y: -5 };
    let mut c = CmpsCnt::<'_, Test, 3>::new();
    let mut u = CmpsUnq::<'_, Test, 3>::new();
    let mut p = CmpsRef::<'_, Test, 3>::new(&mut t);
    println!("sizeof p = {}", size_of::<CmpsRef::<Test, 3>>());
    println!("sizeof c = {}", size_of::<CmpsCnt::<Test, 3>>());
    println!("sizeof u = {}", size_of::<CmpsUnq::<Test, 3>>());
    println!("p.x = {}, p.y = {}", p.x, p.y);
    p.x = 97;
    p.y = 53;
    println!("p.x = {}, p.y = {}", p.x, p.y);
    p.set_ptr(&mut z);
    println!("p.x = {}, p.y = {}", p.x, p.y);
    c.x = 9;
    c.y = 8;
    println!("c.x = {}, c.y = {}", c.x, c.y);
    u.x = 1;
    u.y = 2;
    println!("u.x = {}, u.y = {}", u.x, u.y);
}
