namespace HackHttp\Tests\Message;

use HackHttp\Tests\Helper;

use namespace HackHttp\Message as HM;
use HackHttp\Message\LimitStream;
use HackHttp\Message\PumpStream;
use function Facebook\FBExpect\expect;
use type Facebook\HackTest\{HackTest, DataProvider};

class PumpStreamTest extends HackTest
{
    private static vec<mixed> $called = vec[];

    public function testHasMetadataAndSize(): void
    {
        $p = new PumpStream( (?int $n): ?string ==> {return null;}, 
                            shape('metadata' => dict['foo' => 'bar'],'size'     => 100));

        Helper::assertSame('bar', $p->getMetadata('foo'));
        Helper::assertSame(dict['foo' => 'bar'], $p->getMetadata());
        Helper::assertSame(100, $p->getSize());
    }

    
    public function testCanReadFromCallable(): void
    {
        $p = new PumpStream( (?int $size): ?string ==> {
            return 'a';
        });

        Helper::assertSame('a', $p->read(1));
        Helper::assertSame(1, $p->tell());
        Helper::assertSame('aaaaa', $p->read(5));
        Helper::assertSame(6, $p->tell());
    }

    
    public function testStoresExcessDataInBuffer(): void
    {
        self::$called = vec[];
        $p = new PumpStream( (?int $size): ?string ==> {
            self::$called[] = $size;
            return 'abcdef';
        });
        Helper::assertSame('a', $p->read(1));
        Helper::assertSame('b', $p->read(1));
        Helper::assertSame('cdef', $p->read(4));
        Helper::assertSame('abcdefabc', $p->read(9));
        Helper::assertSame(vec[1, 9, 3], self::$called);
    }

    
    public function testInifiniteStreamWrappedInLimitStream(): void
    {
        $p = new PumpStream( (?int $n): ?string ==> {
            return 'a';
        });

        $s = new LimitStream($p, 5);
        Helper::assertSame('aaaaa',  $s->__toString());
    }

    public function testDescribesCapabilities(): void
    {
        $p = new PumpStream( (?int $n): ?string ==> { return null;});

        Helper::assertTrue($p->isReadable());
        Helper::assertFalse($p->isSeekable());
        Helper::assertFalse($p->isWritable());
        Helper::assertNull($p->getSize());
        Helper::assertSame('', $p->getContents());
        Helper::assertSame('',  $p->__toString());
        $p->close();
        Helper::assertTrue($p->eof());
        expect($p->read(10))->toBeEmpty();
    }
    
}
