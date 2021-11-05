namespace HackHttp\Client;

use HackPromises\PromiseInterface;
use HackHttp\Message\RequestInterface;
use HackHttp\Message\ResponseInterface;
use HackHttp\Message\UriInterface;

/**
 * Client interface for sending HTTP requests.
 */
interface ClientInterface
{
    /**
     * Send an HTTP request.
     *
     * @param RequestInterface $request Request to send
     * @param dict<arraykey,  mixed>   $options Request options to apply to the given
     *                                  request and to the transfer.
     * @return ResponseInterface
     * @throws ClientException
     */
    public function send(RequestInterface $request, dict<arraykey,  mixed> $options = dict[]): ResponseInterface;

    /**
     * Asynchronously send an HTTP request.
     *
     * @param RequestInterface $request Request to send
     * @param dict<arraykey,  mixed>             $options Request options to apply to the given
     *                                  request and to the transfer.
     * @return PromiseInterface
     */
    public function sendAsync(RequestInterface $request, dict<arraykey,  mixed> $options = dict[]): PromiseInterface;

    /**
     * Create and send an HTTP request.
     *
     * Use an absolute path to override the base path of the client, or a
     * relative path to append to the base path of the client. The URL can
     * contain the query string as well.
     *
     * @param string              $method  HTTP method.
     * @param mixed $uri     URI object or string.
     * @param dict<arraykey,  mixed>                $options Request options to apply.
     *
     * @return ResposeInterface
     */
    public function request(string $method, mixed $uri, dict<arraykey,  mixed> $options = dict[]): ResponseInterface;

    /**
     * Create and send an asynchronous HTTP request.
     *
     * Use an absolute path to override the base path of the client, or a
     * relative path to append to the base path of the client. The URL can
     * contain the query string as well. Use an array to provide a URL
     * template and additional variables to use in the URL template expansion.
     *
     * @param string              $method  HTTP method
     * @param mixed $uri     URI object or string.
     * @param dict<arraykey,  mixed>                $options Request options to apply.
     *
     * @return PromiseInterface
     */
    public function requestAsync(string $method, mixed $uri, dict<arraykey,  mixed> $options = dict[]): PromiseInterface;

}
