/*
Copyright (C) AD 2022 Claudiu-Stefan Costea

This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at https://mozilla.org/MPL/2.0/.
*/
pub mod cmpsptr {
    use std::ops::{Deref, DerefMut};
    use std::marker::PhantomData;

    static mut _GLOBAL_MASK: usize = usize::MAX;

    fn check_global_mask<const CMPS_LEVEL: i32>(ptr: usize) -> bool {
        let shift_bits = 32 + CMPS_LEVEL;
        unsafe {
            if _GLOBAL_MASK == usize::MAX {
                _GLOBAL_MASK = (ptr >> shift_bits) << shift_bits;
                true
            } else {
                _GLOBAL_MASK == (ptr >> shift_bits) << shift_bits
            }
        }
    }

    fn apply_global_mask(ptr: usize) -> usize {
        unsafe {
            ptr | _GLOBAL_MASK
        }
    }

    //#[derive(Copy, Clone)]
    pub struct CmpsPtr<'a, T: 'a, const CMPS_LEVEL: i32> {
        _phantom: PhantomData<&'a T>,
        _ptr: u32
    }

    impl<T, const CMPS_LEVEL: i32> CmpsPtr<'_, T, CMPS_LEVEL> {

        pub fn ptr(&self) -> &T {
            unsafe {
                let p = apply_global_mask((self._ptr as usize) << CMPS_LEVEL);
                //println!("get p = {:#b}", p);
                &*(p as *const T)
            }
        }

        pub fn ptr_mut(&self) -> &mut T {
            unsafe {
                let p = apply_global_mask((self._ptr  as usize) << CMPS_LEVEL);
                //println!("get mut p = {:#b}", p);
                &mut *(p as *mut T)
            }
        }

        fn compress(ptr: &mut T) -> u32 {
            let p = (ptr as *mut T) as usize;
            //println!("set mut p = {:#b}", p);
            if check_global_mask::<CMPS_LEVEL>(p) {
                (p >> CMPS_LEVEL) as u32
            } else {
                panic!("CANNOT COMPRESS POINTER {}!", p)
            }
        }

        pub fn set_ptr(&mut self, ptr: &mut T) {
            self._ptr = CmpsPtr::<'_, T, CMPS_LEVEL>::compress(ptr);
        }

        pub fn new(ptr: &mut T) -> CmpsPtr<'_, T, CMPS_LEVEL> {
            CmpsPtr::<'_, T, CMPS_LEVEL> {
                _ptr: CmpsPtr::<'_, T, CMPS_LEVEL>::compress(ptr),
                _phantom: PhantomData
            }
        }

        fn new_copy<'a>(ptr: u32) -> CmpsPtr<'a, T, CMPS_LEVEL> {
            CmpsPtr::<'a, T, CMPS_LEVEL> {
                _phantom: PhantomData,
                _ptr: ptr
            }
        }

    }

    impl<T, const CMPS_LEVEL: i32> Copy for CmpsPtr<'_, T, CMPS_LEVEL> {}

    impl<'a, T, const CMPS_LEVEL: i32> Clone for CmpsPtr<'a, T, CMPS_LEVEL> {
        fn clone(&self) -> CmpsPtr<'a, T, CMPS_LEVEL> {
            CmpsPtr::<'a, T, CMPS_LEVEL>::new_copy(self._ptr)
        }
    } 

    impl<T, const CMPS_LEVEL: i32> Deref for CmpsPtr<'_, T, CMPS_LEVEL> {
        type Target = T;
        fn deref(&self) -> &Self::Target {
            self.ptr()
        }
    }

    impl<T, const CMPS_LEVEL: i32> DerefMut for CmpsPtr<'_, T, CMPS_LEVEL> {
        fn deref_mut(&mut self) -> &mut Self::Target {
            self.ptr_mut()
        }
    }

}