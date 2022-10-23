mod cmpsptr;

use std::mem::size_of;

use cmpsptr::cmpsptr::CmpsPtr;


struct Test {
    x: i32,
    y: i32
}

fn main() {
    let mut t = Test {x: 5, y: 9 };
    let mut z = Test {x: -3, y: -5 };
    let mut p = CmpsPtr::<'_, Test, 3>::new(&mut t);
    println!("sizeof p = {}", size_of::<CmpsPtr::<Test, 3>>());
    println!("x = {}, y = {}", p.x, p.y);
    p.x = 97;
    p.y = 53;
    println!("x = {}, y = {}", p.x, p.y);
    p.set_ptr(&mut z);
    println!("x = {}, y = {}", p.x, p.y);
}
