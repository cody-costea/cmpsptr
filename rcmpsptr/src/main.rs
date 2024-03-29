mod cmpsptr;

use cmpsptr::cmpsptr::{CmpsRef, CmpsUnq, CmpsRfc, CmpsCnt, CmpsShr, CmpsCow, Counter};
use std::sync::atomic::{AtomicU32};

use std::mem::size_of;

struct Test {
    x: i32,
    y: i32,
    cnt: u32
}

impl Counter for Test {

    fn increase_count(&mut self) -> usize {
        let cnt = self.cnt + 1;
        self.cnt = cnt;
        cnt as usize
    }

    fn decrease_count(&mut self) -> usize {
        let cnt = self.cnt - 1;
        self.cnt = cnt;
        cnt as usize
    }

    fn current_count(&self) -> usize {
        self.cnt as usize
    }

    unsafe fn reset_count(&mut self) {
        self.cnt = 1;
    }
}

impl Clone for Test {
    fn clone(&self) -> Test {
        Test {
            x: self.x,
            y: self.y,
            cnt: 0
        }
    }
}

fn main() {
    unsafe {
        let mut t = Test { x: 5, y: 9, cnt: 1 };
        let mut z = Test { x: -3, y: -5, cnt: 1 };
        let mut u = CmpsUnq::<'_, Test, 3>::new();
        let mut c = CmpsCow::<CmpsCnt::<'_, Test, 3>, true>::new();
        let mut s = CmpsShr::<'_, Test, AtomicU32, 3>::new();
        let mut p = CmpsRef::<'_, Test, 3>::new(&mut t);
        println!("sizeof p = {}", size_of::<CmpsRef::<Test, 3>>());
        println!("sizeof c = {}", size_of::<CmpsCnt::<Test, 3>>());
        println!("sizeof s = {}", size_of::<CmpsShr::<Test, AtomicU32, 3>>());
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
        s.x = -9;
        s.y = -5;
        println!("s.x = {}, s.y = {}", s.x, s.y);
        u.x = 1;
        u.y = 2;
        println!("u.x = {}, u.y = {}", u.x, u.y);
    }
}
