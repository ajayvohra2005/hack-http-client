namespace HackHttp\Tests\Message;

use HackHttp\Tests\Helper;

use namespace HackHttp\Message as HM;
use HackHttp\Message\MultipartStream;
use function Facebook\FBExpect\expect;
use type Facebook\HackTest\{HackTest, DataProvider};

class MultipartStreamTest extends HackTest
{
    public function testCreatesDefaultBoundary(): void
    {
        $b = new MultipartStream();
        Helper::assertNotEmpty($b->getBoundary());
    }

    public function testCanProvideBoundary(): void
    {
        $b = new MultipartStream(vec[], 'foo');
        Helper::assertSame('foo', $b->getBoundary());
    }

    public function testIsNotWritable(): void
    {
        $b = new MultipartStream();
        Helper::assertFalse($b->isWritable());
    }

    public function testCanCreateEmptyStream(): void
    {
        $b = new MultipartStream();
        $boundary = $b->getBoundary();
        expect($boundary)->toNotBeEmpty();
        if($boundary is string) {
            Helper::assertSame("--{$boundary}--\r\n", $b->getContents());
            Helper::assertSame(\strlen($boundary) + 6, $b->getSize());
        }
    }

    public function testValidatesFilesArrayElement(): void
    {
        expect(() ==> new MultipartStream(vec[dict['foo' => 'bar']]))->toThrow(\InvalidArgumentException::class);
    }

    public function testEnsuresFileHasName(): void
    {
        expect(() ==> new MultipartStream(vec[dict['contents' => 'bar']]))->toThrow(\InvalidArgumentException::class);
    }

    public function testSerializesFields(): void
    {
        $b = new MultipartStream(vec[
            dict[
                'name'     => 'foo',
                'contents' => 'bar'
            ],
            dict[
                'name' => 'baz',
                'contents' => 'bam'
            ]
        ], 'boundary');
        Helper::assertSame(
            "--boundary\r\nContent-Disposition: form-data; name=\"foo\"\r\nContent-Length: 3\r\n\r\n"
            . "bar\r\n--boundary\r\nContent-Disposition: form-data; name=\"baz\"\r\nContent-Length: 3"
            . "\r\n\r\nbam\r\n--boundary--\r\n",
            $b->__toString()
        );
    }

    public function testSerializesNonStringFields(): void
    {
        $b = new MultipartStream(vec[
            dict[
                'name'     => 'int',
                'contents' =>  1
            ],
            dict[
                'name' => 'bool',
                'contents' =>  false
            ],
            dict[
                'name' => 'bool2',
                'contents' =>  true
            ],
            dict[
                'name' => 'float',
                'contents' => 1.1
            ]
        ], 'boundary');
        Helper::assertSame(
            "--boundary\r\nContent-Disposition: form-data; name=\"int\"\r\nContent-Length: 1\r\n\r\n"
            . "1\r\n--boundary\r\nContent-Disposition: form-data; name=\"bool\"\r\n\r\n\r\n--boundary"
            . "\r\nContent-Disposition: form-data; name=\"bool2\"\r\nContent-Length: 1\r\n\r\n"
            . "1\r\n--boundary\r\nContent-Disposition: form-data; name=\"float\"\r\nContent-Length: 3"
            . "\r\n\r\n1.1\r\n--boundary--\r\n",
            $b->__toString()
        );
    }
}
