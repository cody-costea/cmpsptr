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

struct RfcTest
{
    public static const SNr[3] testArr = [9, 8, 7];

    Ptr!(UnqTest, -1, -1) y = void;

    SNr x = void;

    this(const SNr x, UnqTest* unqTest)
    {
        this.y = unqTest;
        printf("this.y.sizeof = %d\n", this.y.sizeof);
        this.x = x;
    }

    //@disable this();

    ~this()
    {
        printf("RfcTest destructor!\n");
        //printf("y.z = %d", y.z);
    }
}

void testFunc(Ptr!(RfcTest, 1) tst, const UNr again)
{
    printf("before tst.count = %d\n", (tst.refCount));
    if (again < 3)
    {
        testFunc(tst, again + 1);
    }    
    printf("after tst.count = %d\n", (tst.refCount));
}

void testHndlFunc(Hnl!("APP.RfcTest.testArr", "APP") tst)
{
    printf("APP.RfcTest.testArr.index = %d\n", (tst.index));
    printf("APP.RfcTest.testArr.sizeof = %d\n", (tst.sizeof));
}

extern (C) int main(string[] args) {
    UnqTest* unq = allocNew!UnqTest(783);    
    printf("unq.sizeof = %d\n", unq.sizeof);
    RfcTest* ptr = allocNew!RfcTest(137, unq);
    printf("ptr.sizeof = %d\n", ptr.sizeof);
    Ptr!(RfcTest, 1, 1) tst = nil;
    auto rfc = tst.ptrOrElse((RfcTest* ptr) { return ptr; }, ptr);
    printf("rfc.x = %d\n", rfc.x);
    printf("before tst.count = %d\n", (tst.refCount));
    testFunc(tst, 0);
    printf("after tst.count = %d\n", (tst.refCount));
    printf("tst.x = %d\n", tst.x);
    tst.x = 873;
    printf("tst.x = %d\n", tst.x);
    printf("tst.sizeof = %d\n", tst.sizeof);
    //Hnl!("APP.RfcTest.testArr", "APP") testArr = 2;
    Hnl!("APP.RfcTest.testArr", "APP") testArr = &(APP.RfcTest.testArr[2]);
    testHndlFunc(testArr);
    SNr testArrElm = testArr;
    printf("testArr = %d\n", testArrElm);
    return 0;
}
