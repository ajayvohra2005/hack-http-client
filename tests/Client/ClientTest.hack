namespace HackHttp\Tests\Client;

use HackHttp\Tests\Helper;
use HackHttp\Tests\Server;

use namespace HackHttp\Client\Exception as HCE;
use namespace HackHttp\Message as HM;

use HackHttp\Client\Client;
use HackHttp\Client\Cookie\CookieJar;
use HackHttp\Client\Exception\RequestException;
use HackHttp\Client\HandlerStack;
use HackHttp\Client\Middleware;
use HackPromises\PromiseInterface;
use HackHttp\Message;
use HackHttp\Message\Request;
use HackHttp\Message\Response;
use HackHttp\Message\ResponseInterface;
use HackHttp\Message\Uri;
use HackHttp\Client\RequestOptions;
use function Facebook\FBExpect\expect;
use type Facebook\HackTest\HackTest;

class ClientTest extends HackTest
{
    <<__Override>>
    public static async function beforeFirstTestAsync(): Awaitable<void> 
    {
        Server::start();
    }

    <<__Override>>
    public static async function afterLastTestAsync(): Awaitable<void> 
    {
        Server::stop();
    }

    public function testUsesDefaultHandler(): void
    {
        $client = new Client();
        Server::enqueue(vec[new Response(200, dict['Content-Length' => vec['0']])]);
        $response = $client->get(Server::$url);
        Helper::assertSame(200, $response->getStatusCode());
    }

    public function testCanSendAsyncGetRequests(): void
    {
        $client = new Client();
        Server::flush();
        Server::enqueue(vec[new Response(200, dict['Content-Length' => vec['2']], 'hi')]);
        $promise = $client->getAsync(Server::$url, dict[RequestOptions::QUERY => dict['test' => 'foo']]);
        $response = $promise->wait();
        expect($response)->toBeInstanceOf(ResponseInterface::class);
        if($response is ResponseInterface) {
            Helper::assertInstanceOf(PromiseInterface::class, $promise);
            Helper::assertSame(200, $response->getStatusCode());
            $received = Server::received();
            Helper::assertCount(1, $received);
            Helper::assertSame('test=foo', $received[0]->getUri()->getQuery());
        }
    }


    public function testMergesDefaultOptionsAndDoesNotOverwriteUa(): void
    {
        $client = new Client(dict[RequestOptions::HEADERS => dict['User-agent' => vec['foo']]]);
        $config = $client->getConfig();
        Helper::assertSame(dict['User-agent' => vec['foo']], $config[RequestOptions::HEADERS]);
        Helper::assertIsArray($config[RequestOptions::ALLOW_REDIRECTS]);
        Helper::assertTrue($config[RequestOptions::HTTP_ERRORS] as bool);
        Helper::assertTrue($config[RequestOptions::DECODE_CONTENT] as bool);
        Helper::assertTrue($config[RequestOptions::VERIFY] as bool);
    }


    public function testDoesNotOverwriteHeaderWithDefaultInRequest(): void
    {
        Server::flush();
        Server::enqueue(vec[new Response()]);
        $client= new Client(dict[RequestOptions::HEADERS => dict['User-agent' => vec['foo']]]);
        $request = new Request('GET', Server::$url, dict['User-Agent' => vec['bar']]);
        $client->send($request);
        Helper::assertSame('bar', Server::received()[0]->getHeaderLine('User-Agent'));
    }


    public function testDoesOverwriteHeaderWithSetRequestOption(): void
    {
        Server::flush();
        Server::enqueue(vec[new Response()]);
        $c = new Client(dict[
            RequestOptions::HEADERS => dict['User-agent' => vec['foo']],
        ]);
        $request = new Request('GET', Server::$url, dict['User-Agent' => vec['bar']]);
        $c->send($request, dict[RequestOptions::HEADERS => dict['User-Agent' => vec['YO']]]);
        Helper::assertSame('YO',  Server::received()[0]->getHeaderLine('User-Agent'));
    }

    public function testValidatesAllowRedirects(): void
    {
        Server::flush();
        Server::enqueue(vec[new Response(200, dict[], 'foo')]);
        $client = new Client();
        expect(() ==> $client->get(Server::$url, dict[RequestOptions::ALLOW_REDIRECTS => 'foo']))->toThrow(\InvalidArgumentException::class, 'allow_redirects must be bool, or dict<string, mixed>');
    }

    public function testThrowsHttpErrorsByDefault(): void
    {
        Server::flush();
        Server::enqueue(vec[new Response(404)]);
        $client = new Client();

        expect(() ==> $client->get(Server::$url))->toThrow(HCE\ClientException::class);
    }


    public function testValidatesCookies(): void
    {
        Server::flush();
        Server::enqueue(vec[new Response(200, dict[], 'foo')]);
        $client = new Client();

        expect(() ==> $client->get(Server::$url, dict[RequestOptions::COOKIES => 'foo']))->toThrow(\InvalidArgumentException::class, 'cookies are not HackHttp\Client\Cookie\CookieJarInterface');
    }

    public function testSetCookieToJar(): void
    {
        Server::flush();
        Server::enqueue(vec[new Response(200, dict['Set-Cookie' => vec['foo=bar']]), new Response()]);
        $client = new Client();
        $jar = new CookieJar();
        $client->get(Server::$url, dict[RequestOptions::COOKIES => $jar]);
        $client->get(Server::$url, dict[RequestOptions::COOKIES => $jar]);
        Helper::assertSame('foo=bar',  Server::received()[1]->getHeaderLine('Cookie'));
    }


    public function testCanDisableContentDecoding(): void
    {
        Server::flush();
        Server::enqueue(vec[new Response()]);
        $client = new Client();
        $client->get(Server::$url, dict[RequestOptions::DECODE_CONTENT => false]);
        $last = Server::received()[0];
        Helper::assertSame(vec[''], $last->getHeader('Accept-Encoding'));
    }


    public function testCanSetContentDecodingToValue(): void
    {
        Server::flush();
        Server::enqueue(vec[new Response()]);
        $client = new Client();
        $client->get(Server::$url, dict[RequestOptions::DECODE_CONTENT => 'gzip']);
        $last = Server::received()[0];
        Helper::assertSame('gzip', $last->getHeaderLine('Accept-Encoding'));
    }

    public function testAddsAcceptEncodingbyCurl(): void
    {
        $client = new Client(dict['curl' => dict[\CURLOPT_ENCODING => '']]);
        Server::flush();
        Server::enqueue(vec[new Response()]);
        $client->get(Server::$url);
        $sent = Server::received()[0];
        Helper::assertTrue($sent->hasHeader('Accept-Encoding'));
    }


    public function testValidatesHeaders(): void
    {
        Server::flush();
        Server::enqueue(vec[new Response()]);
        $client = new Client();

        expect(() ==> $client->get(Server::$url, dict[RequestOptions::HEADERS => 'foo']))->toThrow(\InvalidArgumentException::class);
    }

    public function testAddsBody(): void
    {
        Server::flush();
        Server::enqueue(vec[new Response()]);
        $client = new Client();
        $request = new Request('PUT', Server::$url);
        $client->send($request, dict[RequestOptions::BODY => 'foo']);
        $last = Server::received()[0];
        Helper::assertSame('foo',  $last->getBody()->__toString());
    }

    public function testValidatesQuery(): void
    {
        Server::flush();
        Server::enqueue(vec[new Response()]);
        $client = new Client();
        $request = new Request('PUT', Server::$url);

        expect(() ==> $client->send($request, dict[RequestOptions::QUERY => false]))->toThrow(\InvalidArgumentException::class);
    }


    public function testQueryCanBeString(): void
    {
        Server::flush();
        Server::enqueue(vec[new Response()]);
        $client = new Client();
        $request = new Request('PUT', Server::$url);
        $client->send($request, dict[RequestOptions::QUERY => 'foo']);
        Helper::assertSame('foo',  Server::received()[0]->getUri()->getQuery());
    }

    
    public function testQueryCanBeArray(): void
    {
        Server::flush();
        Server::enqueue(vec[new Response()]);
        $client = new Client();
        $request = new Request('PUT', Server::$url);
        $client->send($request, dict[RequestOptions::QUERY => dict['foo' => 'bar baz']]);
        Helper::assertSame('foo=bar%20baz',  Server::received()[0]->getUri()->getQuery());
    }


    public function testCanAddJsonData(): void
    {
        Server::flush();
        Server::enqueue(vec[new Response()]);
        $client = new Client();
        $request = new Request('PUT', Server::$url);
        $client->send($request, dict[RequestOptions::JSON => dict['foo' => 'bar']]);
        Helper::assertSame('{"foo":"bar"}', Server::received()[0]->getBody()->__toString());
        Helper::assertSame('application/json', Server::received()[0]->getHeaderLine('Content-Type'));
    }


    public function testCanAddJsonDataWithoutOverwritingContentType(): void
    {
        Server::flush();
        Server::enqueue(vec[new Response()]);
        $client = new Client();
        $request = new Request('PUT', Server::$url);
        $client->send($request, dict[
            RequestOptions::HEADERS => dict['content-type' => vec['foo']],
            RequestOptions::JSON    => 'a'
        ]);
        $last = Server::received()[0];
        Helper::assertSame('"a"', Server::received()[0]->getBody()->__toString());
        Helper::assertSame('foo', $last->getHeaderLine('Content-Type'));
    }

    
    public function testCanAddJsonDataWithNullHeader(): void
    {
        Server::flush();
        Server::enqueue(vec[new Response()]);
        $client = new Client();
        $request = new Request('PUT', Server::$url);
        $client->send($request, dict[
            RequestOptions::HEADERS => null,
            RequestOptions::JSON    => 'a'
        ]);
        $last = Server::received()[0];
        Helper::assertSame('"a"', Server::received()[0]->getBody()->__toString());
        Helper::assertSame('application/json', $last->getHeaderLine('Content-Type'));
    }

    public function testAuthCanBeTrue(): void
    {
        Server::flush();
        Server::enqueue(vec[new Response()]);
        $client = new Client();
        $client->get(Server::$url, dict[RequestOptions::AUTH => false]);
        $last = Server::received()[0];
        Helper::assertFalse($last->hasHeader('Authorization'));
    }

    public function testAuthCanBeArrayForBasicAuth(): void
    {
        Server::flush();
        Server::enqueue(vec[new Response()]);
        $client = new Client();
        $client->get(Server::$url, dict[RequestOptions::AUTH => vec['a', 'b']]);
        $last = Server::received()[0];
        Helper::assertSame('Basic YTpi', $last->getHeaderLine('Authorization'));
    }

    public function testAuthCanBeArrayForDigestAuth(): void
    {
        Server::flush();
        Server::enqueue(vec[new Response()]);
        $client = new Client();
        $client->get(Server::$url, dict[RequestOptions::AUTH => vec['a', 'b', 'digest']]);
    }

    public function testAuthCanBeArrayForNtlmAuth(): void
    {
        Server::flush();
        Server::enqueue(vec[new Response()]);
        $client = new Client();
        $client->get(Server::$url, dict[RequestOptions::AUTH => vec['a', 'b', 'ntlm']]);
    }

    public function testAuthCanBeCustomType(): void
    {
        Server::flush();
        Server::enqueue(vec[new Response()]);
        $client = new Client();
        $client->get(Server::$url, dict[RequestOptions::AUTH => 'foo']);
    }

    public function testCanAddFormParams(): void
    {
        Server::flush();
        Server::enqueue(vec[new Response()]);
        $client = new Client();
        $client->post(Server::$url, dict[
            RequestOptions::FORM_PARAMS => dict[
                'foo' => 'bar bam',
                'baz' => dict['boo' => 'qux']
            ]
        ]);
        $last = Server::received()[0];
        Helper::assertSame(
            'application/x-www-form-urlencoded',
            $last->getHeaderLine('Content-Type')
        );
        Helper::assertSame(
            'foo=bar+bam&baz%5Bboo%5D=qux',
            $last->getBody()->__toString()
        );
    }

    public function testFormParamsEncodedProperly(): void
    {
        $separator = \ini_get('arg_separator.output');
        \ini_set('arg_separator.output', '&amp;');
        Server::flush();
        Server::enqueue(vec[new Response()]);
        $client = new Client();
        $client->post(Server::$url, dict[
            RequestOptions::FORM_PARAMS => dict[
                'foo' => 'bar bam',
                'baz' => dict['boo' => 'qux']
            ]
        ]);
        $last = Server::received()[0];
        Helper::assertSame(
            'foo=bar+bam&baz%5Bboo%5D=qux',
            $last->getBody()->__toString()
        );

        \ini_set('arg_separator.output', $separator);
    }


    public function testCanSendMultipart(): void
    {
        Server::flush();
        Server::enqueue(vec[new Response()]);
        $client = new Client();
        $client->post(Server::$url, dict[
            RequestOptions::MULTIPART => vec[
                dict[
                    'name'     => 'foo',
                    'contents' => 'bar'
                ],
                dict[
                    'name'     => 'test',
                    'contents' => HM\Utils::streamFor(HM\Utils::getFileHandle(__FILE__))
                ]
            ]
        ]);

        $last = Server::received()[0];
        Helper::assertStringContainsString(
            'multipart/form-data; boundary=',
            $last->getHeaderLine('Content-Type')
        );

        Helper::assertStringContainsString(
            'Content-Disposition: form-data; name="foo"',
            $last->getBody()->__toString()
        );

        Helper::assertStringContainsString('bar', $last->getBody()->__toString());
        Helper::assertStringContainsString(
            'Content-Disposition: form-data; name="foo"' . "\r\n",
            $last->getBody()->__toString()
        );
        Helper::assertStringContainsString(
            'Content-Disposition: form-data; name="test"; filename="ClientTest.php"',
            $last->getBody()->__toString()
        );
    }

    public function testCanSendMultipartWithExplicitBody(): void
    {
        Server::flush();
        Server::enqueue(vec[new Response()]);
        $client = new Client();
        $client->send(
            new Request(
                'POST',
                Server::$url,
                dict[],
                new HM\MultipartStream(
                    vec[
                        dict[
                            'name' => 'foo',
                            'contents' => 'bar',
                        ],
                        dict[
                            'name' => 'test',
                            'contents' => HM\Utils::streamFor(HM\Utils::getFileHandle(__FILE__)),
                        ],
                    ]
                )
            )
        );

        $last = Server::received()[0];
        Helper::assertStringContainsString(
            'multipart/form-data; boundary=',
            $last->getHeaderLine('Content-Type')
        );

        Helper::assertStringContainsString(
            'Content-Disposition: form-data; name="foo"',
            $last->getBody()->__toString()
        );

        Helper::assertStringContainsString('bar', $last->getBody()->__toString());
        Helper::assertStringContainsString(
            'Content-Disposition: form-data; name="foo"' . "\r\n",
            $last->getBody()->__toString()
        );
        Helper::assertStringContainsString(
            'Content-Disposition: form-data; name="test"; filename="ClientTest.php"',
            $last->getBody()->__toString()
        );
    }
   
    public function testSendWithInvalidHeader(): void
    {
        Server::flush();
        Server::enqueue(vec[new Response()]);
        $client = new Client();
        $request = new Request('GET', Server::$url);

        expect(() ==> $client->send($request, dict[RequestOptions::HEADERS=> vec['X-Foo: Bar']]))->
            toThrow(\InvalidArgumentException::class, 'headers must be a dict<arraaykey, mixed>');
    }

    public function testProperlyBuildsQuery(): void
    {
        Server::flush();
        Server::enqueue(vec[new Response()]);
        $client = new Client();
        $request = new Request('PUT', Server::$url);
        $client->send($request, dict[RequestOptions::QUERY => dict['foo' => 'bar', 'john' => 'doe']]);
        Helper::assertSame('foo=bar&john=doe',  Server::received()[0]->getUri()->getQuery());
    }

    
    public function testValidatesSink(): void
    {
        Server::flush();
        Server::enqueue(vec[new Response()]);
        $client = new Client();

        expect(() ==> $client->get(Server::$url, dict[RequestOptions::SINK => true]))->toThrow(\InvalidArgumentException::class);
    }

    public function testResponseBodyAsString(): void
    {
        $responseBody = '{ "package": "hack-http" }';
        Server::flush();
        Server::enqueue(vec[new Response(200, dict['Content-Type' => vec['application/json']], $responseBody)]);
        $client = new Client();
        $request = new Request('GET', Server::$url);
        $response = $client->send($request, dict[RequestOptions::JSON => dict['a' => 'b']]);

        Helper::assertSame($responseBody,  $response->getBody()->__toString());
    }

    public function testResponseContent(): void
    {
        $responseBody = '{ "package": "hack-htttp" }';
        Server::enqueue(vec[new Response(200, dict['Content-Type' => vec['application/json']], $responseBody)]);
        $client = new Client();
        $request = new Request('POST', Server::$url);
        $response = $client->send($request, dict[RequestOptions::JSON => dict['a' => 'b']]);

        Helper::assertSame($responseBody, $response->getBody()->getContents());
    }
}
