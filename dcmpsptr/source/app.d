module APP;
import core.stdc.stdio;
import cmpsptr;

struct UnqTest
{
    SNr z = void;

    ~this()
    {
        printf("UnqTest destructor!\n");
    }
}

struct NewTest
{
    SNr _n = 315;

    SNr n()
    {
        return this._n;
    }

    void n(SNr n)
    {
        this._n = n;
    }

    ~this()
    {
        printf("NewTest destructor!\n");
    }
}

struct RfcTest
{
    public static const SNr[3] testArr = [9, 8, 7];

    @Dispatch Ptr!(UnqTest, Own.fixedUnique, Opt.lazyInit) y = void;
    @Dispatch NewTest nTest;
    SNr x = void;

    mixin ForwardDispatch;

    this(const SNr x, UnqTest* unqTest)
    {
        this.y = unqTest;
        printf("this.y.sizeof = %d\n", this.y.sizeof);
        this.x = x;
    }

    @disable this();

    ~this()
    {
        printf("RfcTest destructor!\n");
    }
}

void testFunc(Ptr!(RfcTest, Own.sharedCounted, Opt.nonNull) tst, const UNr again)
{
    printf("before tst.count = %d\n", (tst.refCount));
    if (again < 3)
    {
        testFunc(tst, again + 1);
    }    
    printf("after tst.count = %d\n", (tst.refCount));
}

void testHndlFunc(Hnd!(APP.RfcTest.testArr) tst)
{
    printf("APP.RfcTest.testArr.index = %d\n", (tst.index));
    printf("APP.RfcTest.testArr.sizeof = %d\n", (tst.sizeof));
}

void doTests()
{
    UnqTest* unq = Mgr!COMPRESS_POINTERS.allocNew!UnqTest(783);
    RfcTest* ptr = Mgr!COMPRESS_POINTERS.allocNew!RfcTest(137, unq);
    Ptr!(RfcTest, Own.sharedCounted, Opt.lazyInit) tst = nil;
    auto rfc = tst.ptrOrElse((RfcTest* ptr) { return ptr; }, ptr);    
    SNr nr = 1000;
    SNr no = 2000;
    tst((ref RfcTest r, SNr nr, SNr no) {   auto z = r.z;
                                            printf("CALL: %d + %d + %d = %d\n", z, nr, no, z + nr + no);
                                        }, nr, no);
    printf("tst.n = %d\n", tst.n);
    printf("before tst.count = %d\n", (tst.refCount));
    testFunc(tst.nonNull, 0);
    printf("after tst.count = %d\n", (tst.refCount));
    printf("tst.x = %d\n", tst.x);
    tst.x = 873;
    printf("rfc.x = %d\n", rfc.x);
    printf("tst.sizeof = %d\n", tst.sizeof);
    Hnd!(APP.RfcTest.testArr) testArr1 = 1;
    Hnd!(APP.RfcTest.testArr) testArr2 = &(APP.RfcTest.testArr[2]);
    testHndlFunc(testArr1);
    testHndlFunc(testArr2);
    SNr testArrElm = testArr1;
    printf("testArr1 = %d\n", testArrElm);
    printf("testArr2 = %d\n", cast(SNr)testArr2);
}

extern (C) int main()
{
    doTests;
    return 0;
}