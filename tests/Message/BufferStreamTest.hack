namespace HackHttp\Tests\Message;

use HackHttp\Tests\Helper;

use HackHttp\Message\BufferStream;
use function Facebook\FBExpect\expect;
use type Facebook\HackTest\{HackTest, DataProvider};

class BufferStreamTest extends HackTest
{
    public function testHasMetadata(): void
    {
        $b = new BufferStream(10);
        Helper::assertTrue($b->isReadable());
        Helper::assertTrue($b->isWritable());
        Helper::assertFalse($b->isSeekable());
        Helper::assertNull($b->getMetadata('foo'));
        Helper::assertSame(10, $b->getMetadata('hwm'));
        Helper::assertSame(dict[], $b->getMetadata());
    }

    public function testRemovesReadDataFromBuffer(): void
    {
        $b = new BufferStream();
        Helper::assertSame(3, $b->write('foo'));
        Helper::assertSame(3, $b->getSize());
        Helper::assertFalse($b->eof());
        Helper::assertSame('foo', $b->read(10));
        Helper::assertTrue($b->eof());
        Helper::assertSame('', $b->read(10));
    }

    public function testCanCastToStringOrGetContents(): void
    {
        $b = new BufferStream();
        $b->write('foo');
        $b->write('baz');
        Helper::assertSame('foo', $b->read(3));
        $b->write('bar');
        Helper::assertSame('bazbar', $b->__toString());
        expect(() ==> $b->tell())->toThrow(\RuntimeException::class, 'Cannot determine the position of a BufferStream');
    }

    public function testDetachClearsBuffer(): void
    {
        $b = new BufferStream();
        $b->write('foo');
        $b->detach();
        Helper::assertTrue($b->eof());
        Helper::assertSame(3, $b->write('abc'));
        Helper::assertSame('abc', $b->read(10));
    }

    public function testExceedingHighwaterMarkReturnsFalseButStillBuffers(): void
    {
        $b = new BufferStream(5);
        Helper::assertSame(3, $b->write('hi '));
        Helper::assertSame(0, $b->write('hello'));
        Helper::assertSame('hi hello', $b->__toString());
        Helper::assertSame(4, $b->write('test'));
    }
}
