namespace HackHttp\Tests\Message;

use namespace HH\Lib\IO;
use namespace HH\Lib\File;

use HackHttp\Tests\Helper;

use HackHttp\Message\Stream;
use HackHttp\Message\Utils;
use function Facebook\FBExpect\expect;
use type Facebook\HackTest\{HackTest, DataProvider};

/**
 * @covers HackHttp\Message\Stream
 */
class StreamTest extends HackTest
{

    public function testConstructorInitializesProperties(): void
    {
        $handle = Utils::getFileHandle();
        expect($handle)->toNotBeNull();

        if($handle is File\Handle) {
            $stream = new Stream($handle);
            Helper::assertTrue($stream->isReadable());
            Helper::assertTrue($stream->isWritable());
            Helper::assertTrue($stream->isSeekable());
            $path = \realpath($handle->getPath());
            Helper::assertSame("file://{$path}", $stream->getMetadata('uri'));
            
            Helper::assertIsArray($stream->getMetadata());
            $stream->write('data');
            Helper::assertSame(4, $stream->getSize());
            Helper::assertTrue($stream->eof());
            $stream->seek(0);
            Helper::assertFalse($stream->eof());
            $stream->close();
        }
    }

    public function testConvertsToString(): void
    {
        $handle = Utils::getFileHandle();
        expect($handle)->toNotBeNull();

        if($handle is File\Handle) {
            $stream = new Stream($handle);
            $stream->write('data');
            Helper::assertSame('data', $stream->__toString());
            $stream->close();
        }
    }

    public function testPipeStream(): void
    {
        $handles = IO\pipe();
        $stream_r = new Stream($handles[0]);
        $stream_w = new Stream($handles[1]);

        Helper::assertTrue($stream_r->isReadable());
        Helper::assertFalse($stream_r->isWritable());

        Helper::assertFalse($stream_w->isReadable());
        Helper::assertTrue($stream_w->isWritable());

        Helper::assertFalse($stream_w->isSeekable());
        Helper::assertFalse($stream_r->isSeekable());
    
        $stream_w->write("foo");
        Helper::assertSame('fo', $stream_r->read(2));
        $stream_w->close();
        $stream_r->close();
    }

    public function testGetsContents(): void
    {
        $handle = Utils::getFileHandle();
        expect($handle)->toNotBeNull();
        if($handle is File\Handle) {
            $stream = new Stream($handle);
            $stream->write('data');
            Helper::assertSame('', $stream->getContents());
            $stream->seek(0);
            Helper::assertSame('data', $stream->getContents());
            Helper::assertSame('', $stream->getContents());
            $stream->close();
        }
    }

    public function testChecksEof(): void
    {
        $handle = Utils::getFileHandle();
        expect($handle)->toNotBeNull();
        if($handle is File\Handle) {
            $stream = new Stream($handle);
            $stream->write('data');
            Helper::assertSame(4, $stream->tell(), 'Stream cursor already at the end');
            Helper::assertTrue($stream->eof(), 'Stream at eof');
            $stream->close();
        }
    }

    public function testEnsuresSizeIsConsistent(): void
    {
        $handle = Utils::getFileHandle();
        expect($handle)->toNotBeNull();
        if($handle is File\Handle) {
            $stream = new Stream($handle);
            $stream->write('foo');
            Helper::assertSame(3, $stream->getSize());
            Helper::assertSame(4, $stream->write('test'));
            Helper::assertSame(7, $stream->getSize());
            Helper::assertSame(7, $stream->getSize());
            $stream->close();
        }
    }

    public function testProvidesStreamPosition(): void
    {
        $handle = Utils::getFileHandle();
        expect($handle)->toNotBeNull();
        if($handle is File\Handle) {
            $stream = new Stream($handle);
            Helper::assertSame(0, $stream->tell());
            $stream->write('foo');
            Helper::assertSame(3, $stream->tell());
            $stream->seek(1);
            Helper::assertSame(1, $stream->tell());
            $stream->close();
        }
    }

    public function testCloseResourceAndClearProperties(): void
    {
        $handle = Utils::getFileHandle();
        expect($handle)->toNotBeNull();
        if($handle is File\Handle) {
            $stream = new Stream($handle);
            $stream->write('foo');
            $stream->close();
            $this->assertStreamStateAfterClosedOrDetached($stream);
        }
    }

    private function assertStreamStateAfterClosedOrDetached(Stream $stream): void
    {
        Helper::assertFalse($stream->isReadable());
        Helper::assertFalse($stream->isWritable());
        Helper::assertFalse($stream->isSeekable());
        Helper::assertNull($stream->getSize());
        Helper::assertNull($stream->getMetadata());
        Helper::assertNull($stream->getMetadata('foo'));

        expect( () ==> $stream->read(10))->toThrow(\RuntimeException::class);
        expect( () ==> $stream->write('bar'))->toThrow(\RuntimeException::class);
        expect( () ==> $stream->seek(10))->toThrow(\RuntimeException::class);
        expect( () ==> $stream->tell())->toThrow(\RuntimeException::class);
        expect( () ==> $stream->eof())->toThrow(\RuntimeException::class);
        expect( () ==> $stream->getContents())->toThrow(\RuntimeException::class);
    }

    public function testStreamReadingWithZeroLength(): void
    {
        $handle = Utils::getFileHandle();
        expect($handle)->toNotBeNull();
        if($handle is File\Handle) {
            $stream = new Stream($handle);
            Helper::assertSame('', $stream->read(0));
            $stream->close();
        }
    }

    public function testStreamReadingWithNegativeLength(): void
    {
        $handle = Utils::getFileHandle();
        expect($handle)->toNotBeNull();
        if($handle is File\Handle) {
            $stream = new Stream($handle);
            expect(() ==> $stream->read(-1))->toThrow(\RuntimeException::class, 'Length parameter cannot be negative');
            $stream->close();
        }
    }

    public function testWriteOnlyStreamIsNotReadable(): void
    {
        $stream = new Stream(IO\request_output());
        Helper::assertFalse($stream->isReadable());
    }

    public function testReadOnlyStreamIsNotWritable(): void
    {
        $stream = new Stream(IO\request_input());
        Helper::assertFalse($stream->isWritable());
    }
}
