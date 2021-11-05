namespace HackHttp\Tests\Message;

use HackHttp\Tests\Helper;

use namespace HackHttp\Message as HM;
use HackHttp\Message\Response;
use function Facebook\FBExpect\expect;
use type Facebook\HackTest\{HackTest, DataProvider};
use HackHttp\Message\StreamInterface;

/**
 * @covers HackHttp\Message\MessageTrait
 * @covers HackHttp\Message\Response
 */
class ResponseTest extends HackTest
{
    public function testDefaultConstructor(): void
    {
        $r = new Response();
        Helper::assertSame(200, $r->getStatusCode());
        Helper::assertSame('1.1', $r->getProtocolVersion());
        Helper::assertSame('OK', $r->getReasonPhrase());
        Helper::assertSame(dict[], $r->getHeaders());
        Helper::assertInstanceOf(StreamInterface::class, $r->getBody());
        Helper::assertSame('', $r->getBody()->__toString());
    }

    public function testCanConstructWithStatusCode(): void
    {
        $r = new Response(404);
        Helper::assertSame(404, $r->getStatusCode());
        Helper::assertSame('Not Found', $r->getReasonPhrase());
    }

    public function testStatusCanBeNumericString(): void
    {
        $r = (new Response())->withStatus(201);

        Helper::assertSame(201, $r->getStatusCode());
        Helper::assertSame('Created', $r->getReasonPhrase());
    }

    public function testCanConstructWithHeaders(): void
    {
        $r = new Response(200, dict['Foo' => vec['Bar']]);
        Helper::assertSame(dict['Foo' => vec['Bar']], $r->getHeaders());
        Helper::assertSame('Bar', $r->getHeaderLine('Foo'));
        Helper::assertSame(vec['Bar'], $r->getHeader('Foo'));
    }

    public function testCanConstructWithHeadersAsArray(): void
    {
        $r = new Response(200, dict[
            'Foo' => vec['baz', 'bar']
        ]);
        Helper::assertSame(dict['Foo' => vec['baz', 'bar']], $r->getHeaders());
        Helper::assertSame('baz, bar', $r->getHeaderLine('Foo'));
        Helper::assertSame(vec['baz', 'bar'], $r->getHeader('Foo'));
    }

    public function testCanConstructWithBody(): void
    {
        $r = new Response(200, dict[], 'baz');
        Helper::assertInstanceOf(StreamInterface::class, $r->getBody());
        Helper::assertSame('baz', $r->getBody()->__toString());
    }

    public function testNullBody(): void
    {
        $r = new Response(200, dict[], null);
        Helper::assertInstanceOf(StreamInterface::class, $r->getBody());
        Helper::assertSame('', $r->getBody()->__toString());
    }

    public function testFalseyBody(): void
    {
        $r = new Response(200, dict[], '0');
        Helper::assertInstanceOf(StreamInterface::class, $r->getBody());
        Helper::assertSame('0', $r->getBody()->__toString());
    }

    public function testCanConstructWithReason(): void
    {
        $r = new Response(200, dict[], null, '1.1', 'bar');
        Helper::assertSame('bar', $r->getReasonPhrase());

        $r = new Response(200, dict[], null, '1.1', '0');
        Helper::assertSame('0', $r->getReasonPhrase(), 'Falsey reason works');
    }

    public function testCanConstructWithProtocolVersion(): void
    {
        $r = new Response(200, dict[], null, '1000');
        Helper::assertSame('1000', $r->getProtocolVersion());
    }

    public function testWithStatusCodeAndNoReason(): void
    {
        $r = (new Response())->withStatus(201);
        Helper::assertSame(201, $r->getStatusCode());
        Helper::assertSame('Created', $r->getReasonPhrase());
    }

    public function testWithStatusCodeAndReason(): void
    {
        $r = (new Response())->withStatus(201, 'Foo');
        Helper::assertSame(201, $r->getStatusCode());
        Helper::assertSame('Foo', $r->getReasonPhrase());

        $r = (new Response())->withStatus(201, '0');
        Helper::assertSame(201, $r->getStatusCode());
        Helper::assertSame('0', $r->getReasonPhrase(), 'Falsey reason works');
    }

    public function testWithProtocolVersion(): void
    {
        $r = (new Response())->withProtocolVersion('1000');
        Helper::assertSame('1000', $r->getProtocolVersion());
    }

    public function testSameInstanceWhenSameProtocol(): void
    {
        $r = new Response();
        Helper::assertSame($r, $r->withProtocolVersion('1.1'));
    }

    public function testWithBody(): void
    {
        $b = HM\Utils::streamFor('0');
        $r = (new Response())->withBody($b);
        Helper::assertInstanceOf(StreamInterface::class, $r->getBody());
        Helper::assertSame('0', $r->getBody()->__toString());
    }

    public function testSameInstanceWhenSameBody(): void
    {
        $r = new Response();
        $b = $r->getBody();
        Helper::assertSame($r, $r->withBody($b));
    }

    public function testWithHeader(): void
    {
        $r = new Response(200, dict['Foo' => vec['Bar']]);
        Helper::assertSame(dict['Foo' => vec['Bar']], $r->getHeaders());

        $r2 = $r->withHeader('baZ', vec['Bam']);
        expect($r2)->toBeInstanceOf(Response::class);
        if($r2 is Response) {
            Helper::assertSame(dict['Foo' => vec['Bar'], 'baZ' => vec['Bam']], $r2->getHeaders());
            Helper::assertSame('Bam', $r2->getHeaderLine('baz'));
            Helper::assertSame(vec['Bam'], $r2->getHeader('baz'));
        }
    }

    public function testWithHeaderAsArray(): void
    {
        $r = new Response(200, dict['Foo' => vec['Bar']]);
        Helper::assertSame(dict['Foo' => vec['Bar']], $r->getHeaders());

        $r2 = $r->withHeader('baZ', vec['Bam', 'Bar']);
        expect($r2)->toBeInstanceOf(Response::class);
        if($r2 is Response) {
            Helper::assertSame(dict['Foo' => vec['Bar'], 'baZ' => vec['Bam', 'Bar']], $r2->getHeaders());
            Helper::assertSame('Bam, Bar', $r2->getHeaderLine('baz'));
            Helper::assertSame(vec['Bam', 'Bar'], $r2->getHeader('baz'));
        }
    }

    public function testWithHeaderReplacesDifferentCase(): void
    {
        $r = new Response(200, dict['Foo' => vec['Bar']]);
        Helper::assertSame(dict['Foo' => vec['Bar']], $r->getHeaders());

        $r2 = $r->withHeader('foO', vec['Bam']);
        expect($r2)->toBeInstanceOf(Response::class);
        if($r2 is Response) {
            Helper::assertSame(dict['foO' => vec['Bam']], $r2->getHeaders());
            Helper::assertSame('Bam', $r2->getHeaderLine('foo'));
            Helper::assertSame(vec['Bam'], $r2->getHeader('foo'));
        }
    }

    public function testWithAddedHeader(): void
    {
        $r = new Response(200, dict['Foo' => vec['Bar']]);
        $r2 = $r->withAddedHeader('foO', vec['Baz']);
        Helper::assertSame(dict['Foo' => vec['Bar']], $r->getHeaders());
        Helper::assertSame(dict['Foo' => vec['Bar', 'Baz']], $r2->getHeaders());
        Helper::assertSame('Bar, Baz', $r2->getHeaderLine('foo'));
        Helper::assertSame(vec['Bar', 'Baz'], $r2->getHeader('foo'));
    }

    public function testWithAddedHeaderAsArray(): void
    {
        $r = new Response(200, dict['Foo' => vec['Bar']]);
        $r2 = $r->withAddedHeader('foO', vec['Baz', 'Bam']);
        Helper::assertSame(dict['Foo' => vec['Bar']], $r->getHeaders());
        Helper::assertSame(dict['Foo' => vec['Bar', 'Baz', 'Bam']], $r2->getHeaders());
        Helper::assertSame('Bar, Baz, Bam', $r2->getHeaderLine('foo'));
        Helper::assertSame(vec['Bar', 'Baz', 'Bam'], $r2->getHeader('foo'));
    }

    public function testWithAddedHeaderThatDoesNotExist(): void
    {
        $r = new Response(200, dict['Foo' => vec['Bar']]);
        $r2 = $r->withAddedHeader('nEw', vec['Baz']);
        Helper::assertSame(dict['Foo' => vec['Bar']], $r->getHeaders());
        Helper::assertSame(dict['Foo' => vec['Bar'], 'nEw' => vec['Baz']], $r2->getHeaders());
        Helper::assertSame('Baz', $r2->getHeaderLine('new'));
        Helper::assertSame(vec['Baz'], $r2->getHeader('new'));
    }

    public function testWithoutHeaderThatExists(): void
    {
        $r = new Response(200, dict['Foo' => vec['Bar'], 'Baz' => vec['Bam']]);
        $r2 = $r->withoutHeader('foO');
        Helper::assertTrue($r->hasHeader('foo'));
        Helper::assertSame(dict['Foo' => vec['Bar'], 'Baz' => vec['Bam']], $r->getHeaders());
        Helper::assertFalse($r2->hasHeader('foo'));
        Helper::assertSame(dict['Baz' => vec['Bam']], $r2->getHeaders());
    }

    public function testWithoutHeaderThatDoesNotExist(): void
    {
        $r = new Response(200, dict['Baz' => vec['Bam']]);
        $r2 = $r->withoutHeader('foO');
        Helper::assertSame($r, $r2);
        Helper::assertFalse($r2->hasHeader('foo'));
        Helper::assertSame(dict['Baz' => vec['Bam']], $r2->getHeaders());
    }

    public function testSameInstanceWhenRemovingMissingHeader(): void
    {
        $r = new Response();
        Helper::assertSame($r, $r->withoutHeader('foo'));
    }

    public function testPassNumericHeaderNameInConstructor(): void
    {
        $r = new Response(200, dict['Location' => vec['foo'], '123' => vec['bar']]);
        Helper::assertSame('bar', $r->getHeaderLine('123'));
    }

    <<DataProvider('invalidHeaderProvider')>>
    public function testConstructResponseInvalidHeader(string $header, vec<string> $headerValue, string $expectedMessage): void
    {
        expect(() ==> new Response(200, dict[$header => $headerValue]))->toThrow(\InvalidArgumentException::class, $expectedMessage);
    }

    public function invalidHeaderProvider(): vec<(string, vec<string>, string)>
    {
        return vec[
            tuple('foo', vec[], 'Header value can not be an empty array.'),
            tuple('', vec[''], '"" is not valid header name')
        ];
    }

    public function testHeaderValuesAreTrimmed(): void
    {
        $r1 = new Response(200, dict['OWS' => vec[" \t \tFoo\t \t "] ]);
        $r2 = (new Response())->withHeader('OWS', vec[" \t \tFoo\t \t "]);
        $r3 = (new Response())->withAddedHeader('OWS', vec[" \t \tFoo\t \t "]);

        expect($r1)->toBeInstanceOf(Response::class);
        expect($r2)->toBeInstanceOf(Response::class);
        expect($r3)->toBeInstanceOf(Response::class);
        if($r1 is Response && $r2 is Response && $r3 is Response) {

            foreach (vec<Response>[$r1, $r2, $r3] as $r) {

                Helper::assertSame(dict['OWS' => vec['Foo']], $r->getHeaders());
                Helper::assertSame('Foo', $r->getHeaderLine('OWS'));
                Helper::assertSame(vec['Foo'], $r->getHeader('OWS'));
            }
        }
    }

    <<DataProvider('invalidStatusCodeRangeProvider')>>
    public function testResponseChangeStatusCodeWithWithInvalidRange(int $invalidValues): void
    {
        $response = new Response();
        expect(() ==> $response->withStatus($invalidValues))->toThrow(\InvalidArgumentException::class, 'Status code must be an integer value between 1xx and 5xx.');
    }

    public function invalidStatusCodeRangeProvider(): vec<(int)>
    {
        return vec[
            tuple(600),
            tuple(99),
        ];
    }
}
