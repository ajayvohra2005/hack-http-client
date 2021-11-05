namespace HackHttp\Tests\Message;

use HackHttp\Tests\Helper;

use namespace HackHttp\Message as HM;
use type HackHttp\Message\{AppendStream, Stream, StreamInterface, Utils};
use function Facebook\FBExpect\expect;
use type Facebook\HackTest\{HackTest, DataProvider};

use namespace HH\Lib\IO;
use namespace HH\Lib\File;

class AppendStreamTest extends HackTest
{
    public function testValidatesStreamsAreReadable(): void
    {
        $a = new AppendStream();
        $s = new Stream(IO\request_output());
        expect($s->isReadable())->toBeFalse();
        expect(() ==> $a->addStream($s))->toThrow(\InvalidArgumentException::class, 'Each stream must be readable');
    }

   
    public function testValidatesSeekType(): void
    {
        $a = new AppendStream();
        expect(() ==> $a->seek(100, \SEEK_CUR))->toThrow(\RuntimeException::class, 'The AppendStream can only seek with SEEK_SET');
    }

    
    public function testTriesToSeekNonseekable(): void
    {
        $a = new AppendStream();
        $s = new Stream(IO\request_input());
        expect($s->isReadable())->toBeTrue();
        expect($s->isSeekable())->toBeFalse();
        $a->addStream($s);
        expect(() ==> $a->seek(10))->toThrow(\RuntimeException::class, 'This AppendStream is not seekable');
    }

  
    public function testSeeksToPositionByReading(): void
    {
        $a = new AppendStream(vec[
            HM\Utils::streamFor('foo'),
            HM\Utils::streamFor('bar'),
            HM\Utils::streamFor('baz'),
        ]);

        $a->seek(3);
        Helper::assertSame(3, $a->tell());
        Helper::assertSame('bar', $a->read(3));

        $a->seek(6);
        Helper::assertSame(6, $a->tell());
        Helper::assertSame('baz', $a->read(3));
    }
 
   
    public function testDetachWithoutStreams(): void
    {
        $s = new AppendStream();
        $s->detach();

        Helper::assertSame(0, $s->getSize());
        Helper::assertTrue($s->eof());
        Helper::assertTrue($s->isReadable());
        Helper::assertSame('', $s->__toString());
        Helper::assertTrue($s->isSeekable());
        Helper::assertFalse($s->isWritable());
    }


    public function testDetachesEachStream(): void
    {
        $handle = Utils::getFileHandle();
        expect($handle)->toNotBeNull();
        if($handle is File\Handle) {
            $s1 = HM\Utils::streamFor($handle);
            $s2 = HM\Utils::streamFor('bar');
            $a = new AppendStream(vec[$s1, $s2]);

            $a->detach();

            Helper::assertSame(0, $a->getSize());
            Helper::assertTrue($a->eof());
            Helper::assertTrue($a->isReadable());
            Helper::assertSame('', $a->__toString());
            Helper::assertTrue($a->isSeekable());
            Helper::assertFalse($a->isWritable());
        }
    }

  
    public function testClosesEachStream(): void
    {
        $handle = Utils::getFileHandle();
        expect($handle)->toNotBeNull();
        if($handle is File\Handle) {
            $s1 = HM\Utils::streamFor($handle);
            $s2 = HM\Utils::streamFor('bar');
            $a = new AppendStream(vec[$s1, $s2]);

            $a->close();

            $this->assertStreamStateAfterClosedOrDetached($s1);
            $this->assertStreamStateAfterClosedOrDetached($s2);
        }
    }

    public function testIsNotWritable(): void
    {
        $a = new AppendStream(vec[HM\Utils::streamFor('foo')]);
        Helper::assertFalse($a->isWritable());
        Helper::assertTrue($a->isSeekable());
        Helper::assertTrue($a->isReadable());
        expect(() ==> $a->write('foo'))->toThrow(\RuntimeException::class, 'Cannot write to an AppendStream');
    }

    public function testDoesNotNeedStreams(): void
    {
        $a = new AppendStream();
        Helper::assertSame('',  $a->__toString());
    }

    public function testCanReadFromMultipleStreams(): void
    {
        $a = new AppendStream(vec[
            HM\Utils::streamFor('foo'),
            HM\Utils::streamFor('bar'),
            HM\Utils::streamFor('baz'),
        ]);
        Helper::assertFalse($a->eof());
        Helper::assertSame(0, $a->tell());
        Helper::assertSame('foo', $a->read(3));
        Helper::assertSame('bar', $a->read(3));
        Helper::assertSame('baz', $a->read(3));
        Helper::assertSame('', $a->read(1));
        Helper::assertTrue($a->eof());
        Helper::assertSame(9, $a->tell());
        Helper::assertSame('foobarbaz', $a->__toString());
    }

    public function testCanDetermineSizeFromMultipleStreams(): void
    {
        $a = new AppendStream(vec[
            HM\Utils::streamFor('foo'),
            HM\Utils::streamFor('bar')
        ]);
        Helper::assertSame(6, $a->getSize());

        $s = new Stream(IO\request_input());
        expect($s->isSeekable())->toBeFalse();
        expect($s->isReadable())->toBeTrue();
        $a->addStream($s);
        Helper::assertNull($a->getSize());
    }

    public function testReturnsEmptyMetadata(): void
    {
        $s = new AppendStream();
        Helper::assertSame(dict[], $s->getMetadata());
        Helper::assertNull($s->getMetadata('foo'));
    }

    private function assertStreamStateAfterClosedOrDetached(StreamInterface $stream): void
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
    
}
