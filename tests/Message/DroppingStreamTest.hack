namespace HackHttp\Tests\Message;

use HackHttp\Tests\Helper;

use HackHttp\Message\BufferStream;
use HackHttp\Message\DroppingStream;
use function Facebook\FBExpect\expect;
use type Facebook\HackTest\{HackTest, DataProvider};

class DroppingStreamTest extends HackTest
{
    public function testBeginsDroppingWhenSizeExceeded(): void
    {
        $stream = new BufferStream();
        $drop = new DroppingStream($stream, 5);
        Helper::assertSame(3, $drop->write('hel'));
        Helper::assertSame(2, $drop->write('lo'));
        Helper::assertSame(5, $drop->getSize());
        Helper::assertSame('hello', $drop->read(5));
        Helper::assertSame(0, $drop->getSize());
        $drop->write('12345678910');
        Helper::assertSame(5, $stream->getSize());
        Helper::assertSame(5, $drop->getSize());
        Helper::assertSame('12345', $drop->__toString());
        Helper::assertSame(0, $drop->getSize());
        $drop->write('hello');
        Helper::assertSame(0, $drop->write('test'));
    }
}
