namespace HackHttp\Tests\Message;

use HackHttp\Tests\Helper;

use HackHttp\Message\LazyOpenStream;
use function Facebook\FBExpect\expect;
use type Facebook\HackTest\{HackTest, DataProvider};

use type HH\Lib\File\WriteMode;

class LazyOpenStreamTest extends HackTest
{
    private ?string $fname;

    <<__Override>>
    public async function beforeEachTestAsync(): Awaitable<void> 
    {
        $this->fname = \tempnam(\sys_get_temp_dir(), 'tfile');

        if (\file_exists($this->fname)) {
            \unlink($this->fname as string);
        }
    }

    <<__Override>>
    public async function afterEachTestAsync(): Awaitable<void> 
    {
        if ($this->fname is string && \file_exists($this->fname)) {
            \unlink($this->fname as string);
        }
    }

    public function testOpensLazily(): void
    {
        expect($this->fname)->toNotBeNull();

        if($this->fname is string) {
            $l = new LazyOpenStream($this->fname, WriteMode::OPEN_OR_CREATE);
            $l->write('foo');
            Helper::assertIsArray($l->getMetadata());
            Helper::assertFileExists($this->fname as string);
            Helper::assertSame('foo', \file_get_contents($this->fname as string));
            Helper::assertSame('foo', $l->__toString());
        }
    }

    public function testProxiesToFile(): void
    {
        expect($this->fname)->toNotBeNull();

        if($this->fname is string) {
            \file_put_contents($this->fname, 'foo');
            $l = new LazyOpenStream($this->fname as string);
            Helper::assertSame('foo', $l->read(4));
            Helper::assertTrue($l->eof());
            Helper::assertSame(3, $l->tell());
            Helper::assertTrue($l->isReadable());
            Helper::assertTrue($l->isSeekable());
            Helper::assertFalse($l->isWritable());
            $l->seek(1);
            Helper::assertSame('oo', $l->getContents());
            Helper::assertSame('foo', $l->__toString());
            Helper::assertSame(3, $l->getSize());
            Helper::assertIsArray($l->getMetadata());
            $l->close();
        }
    }
}
