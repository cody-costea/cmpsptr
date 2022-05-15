On 64bit systems, raw pointers require an amount of 8 bytes (or 64 bits). This allows us to use more than 4GB RAM, however many applications actually require much less than this amount. As professor Donald Knuth stated, ["*It is absolutely idiotic to have 64-bit pointers when I compile a program that uses less than 4 gigabytes of RAM. When such pointer values appear inside a struct, **they not only waste half the memory, they effectively throw away half of the cache**.*"](https://www-cs-faculty.stanford.edu/~knuth/news08.html) (emphasis mine). Thus, to avoid unnecessary waste of memory in such cases, pointers should store only 4 bytes (or 32 bits), and as this also allows a more efficient use of the CPU cache, it can lead to increased performance, despite the additional operations required for pointer compression.

The purpose of this project is to provide solutions for compressing 64bit pointers into 32bit integers, in unmanaged languages which allow the implementation of custom "smart" pointers, such as C++, D (for ["betterC" mode](https://dlang.org/spec/betterc.html)) and Rust (planned). An option is to implement a method similar to [the one used by the JVM](https://wiki.openjdk.java.net/display/HotSpot/CompressedOops). Basically, since on 64bit systems, pointers have at least the 3 lower bits always as zero, we can choose to shift these bits, and use them instead to simulate 35bit addresses, allowing us to use 32GB of RAM with 32bit integers. This works ok, as long as the total amount of memory (including both RAM and virtual memory) available is not higher than this amount.

A safer solution on 64bit systems having more than 32GB RAM, would be to also use a dynamic array of 64bit pointers, and store a 31bit index to this array. In this case, we have to sacrifice 1 bit from the 32bit integer, to specify wether we're storing an address smaller than 16GB, or alternatively we're storing the index to the dynamic array. Even when a pointer is stored in this array, the advantage is it will theoretically require 8 bytes only once. Nonetheless, this solution is not ideal, especially when access to the array needs to be thread-safe.
