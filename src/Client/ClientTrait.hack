
namespace HackHttp\Client;

use HackHttp\Client\ClientException;
use HackPromises\PromiseInterface;
use HackHttp\Message\ResponseInterface;
use HackHttp\Message\UriInterface;

/**
 * Client interface for sending HTTP requests.
 */
trait ClientTrait
{
    /**
     * Create and send an HTTP request.
     *
     * Use an absolute path to override the base path of the client, or a
     * relative path to append to the base path of the client. The URL can
     * contain the query string as well.
     *
     * @param string              $method  HTTP method.
     * @param mixed $uri     URI object or string.
     * @param dict<arraykey,  mixed>               $options Request options to apply.
     *
     * @return ResponseInterface
     * @throws ClientException
     */
    abstract public function request(string $method, mixed $uri, dict<arraykey,  mixed> $options = dict[]): ResponseInterface;

    /**
     * Create and send an HTTP GET request.
     *
     * Use an absolute path to override the base path of the client, or a
     * relative path to append to the base path of the client. The URL can
     * contain the query string as well.
     *
     * @param mixed $uri     URI object or string.
     * @param dict<arraykey,  mixed>               $options Request options to apply.
     *
     * @return ResponseInterface
     * @throws ClientException
     */
    public function get(mixed $uri, dict<arraykey,  mixed> $options = dict[]): ResponseInterface
    {
        return $this->request('GET', $uri, $options);
    }

    /**
     * Create and send an HTTP HEAD request.
     *
     * Use an absolute path to override the base path of the client, or a
     * relative path to append to the base path of the client. The URL can
     * contain the query string as well.
     *
     * @param mixed $uri     URI object or string.
     * @param dict<arraykey,  mixed>               $options Request options to apply.
     *
     * @return ResponseInterface
     * @throws ClientException
     */
    public function head(mixed $uri, dict<arraykey,  mixed> $options = dict[]): ResponseInterface
    {
        return $this->request('HEAD', $uri, $options);
    }

    /**
     * Create and send an HTTP PUT request.
     *
     * Use an absolute path to override the base path of the client, or a
     * relative path to append to the base path of the client. The URL can
     * contain the query string as well.
     *
     * @param mixed $uri     URI object or string.
     * @param dict<arraykey,  mixed>               $options Request options to apply.
     *
     * @return ResponseInterface
     * @throws ClientException
     */
    public function put(mixed $uri, dict<arraykey,  mixed> $options = dict[]): ResponseInterface
    {
        return $this->request('PUT', $uri, $options);
    }

    /**
     * Create and send an HTTP POST request.
     *
     * Use an absolute path to override the base path of the client, or a
     * relative path to append to the base path of the client. The URL can
     * contain the query string as well.
     *
     * @param mixed $uri     URI object or string.
     * @param dict<arraykey,  mixed>               $options Request options to apply.
     *
     * @return ResponseInterface
     * @throws ClientException
     */
    public function post(mixed $uri, dict<arraykey,  mixed> $options = dict[]): ResponseInterface
    {
        return $this->request('POST', $uri, $options);
    }

    /**
     * Create and send an HTTP PATCH request.
     *
     * Use an absolute path to override the base path of the client, or a
     * relative path to append to the base path of the client. The URL can
     * contain the query string as well.
     *
     * @param mixed $uri     URI object or string.
     * @param dict<arraykey,  mixed>               $options Request options to apply.
     *
     * @return ResponseInterface
     * @throws ClientException
     */
    public function patch(mixed $uri, dict<arraykey,  mixed> $options = dict[]): ResponseInterface
    {
        return $this->request('PATCH', $uri, $options);
    }

    /**
     * Create and send an HTTP DELETE request.
     *
     * Use an absolute path to override the base path of the client, or a
     * relative path to append to the base path of the client. The URL can
     * contain the query string as well.
     *
     * @param mixed $uri     URI object or string.
     * @param dict<arraykey,  mixed>               $options Request options to apply.
     *
     * @return ResponseInterface
     * @throws ClientException
     */
    public function delete(mixed $uri, dict<arraykey,  mixed> $options = dict[]): ResponseInterface
    {
        return $this->request('DELETE', $uri, $options);
    }

    /**
     * Create and send an asynchronous HTTP request.
     *
     * Use an absolute path to override the base path of the client, or a
     * relative path to append to the base path of the client. The URL can
     * contain the query string as well. Use an dict<arraykey,  mixed> to provide a URL
     * template and additional variables to use in the URL template expansion.
     *
     * @param string              $method  HTTP method
     * @param mixed $uri     URI object or string.
     * @param dict<arraykey,  mixed>               $options Request options to apply.
     */
    abstract public function requestAsync(string $method, mixed $uri, dict<arraykey,  mixed> $options = dict[]): PromiseInterface;

    /**
     * Create and send an asynchronous HTTP GET request.
     *
     * Use an absolute path to override the base path of the client, or a
     * relative path to append to the base path of the client. The URL can
     * contain the query string as well. Use an dict<arraykey,  mixed> to provide a URL
     * template and additional variables to use in the URL template expansion.
     *
     * @param mixed $uri     URI object or string.
     * @param dict<arraykey,  mixed>               $options Request options to apply.
     */
    public function getAsync(mixed $uri, dict<arraykey,  mixed> $options = dict[]): PromiseInterface
    {
        return $this->requestAsync('GET', $uri, $options);
    }

    /**
     * Create and send an asynchronous HTTP HEAD request.
     *
     * Use an absolute path to override the base path of the client, or a
     * relative path to append to the base path of the client. The URL can
     * contain the query string as well. Use an dict<arraykey,  mixed> to provide a URL
     * template and additional variables to use in the URL template expansion.
     *
     * @param mixed $uri     URI object or string.
     * @param dict<arraykey,  mixed>               $options Request options to apply.
     */
    public function headAsync(mixed $uri, dict<arraykey,  mixed> $options = dict[]): PromiseInterface
    {
        return $this->requestAsync('HEAD', $uri, $options);
    }

    /**
     * Create and send an asynchronous HTTP PUT request.
     *
     * Use an absolute path to override the base path of the client, or a
     * relative path to append to the base path of the client. The URL can
     * contain the query string as well. Use an dict<arraykey,  mixed> to provide a URL
     * template and additional variables to use in the URL template expansion.
     *
     * @param mixed $uri     URI object or string.
     * @param dict<arraykey,  mixed>               $options Request options to apply.
     */
    public function putAsync(mixed $uri, dict<arraykey,  mixed> $options = dict[]): PromiseInterface
    {
        return $this->requestAsync('PUT', $uri, $options);
    }

    /**
     * Create and send an asynchronous HTTP POST request.
     *
     * Use an absolute path to override the base path of the client, or a
     * relative path to append to the base path of the client. The URL can
     * contain the query string as well. Use an dict<arraykey,  mixed> to provide a URL
     * template and additional variables to use in the URL template expansion.
     *
     * @param mixed $uri     URI object or string.
     * @param dict<arraykey,  mixed>               $options Request options to apply.
     */
    public function postAsync(mixed $uri, dict<arraykey,  mixed> $options = dict[]): PromiseInterface
    {
        return $this->requestAsync('POST', $uri, $options);
    }

    /**
     * Create and send an asynchronous HTTP PATCH request.
     *
     * Use an absolute path to override the base path of the client, or a
     * relative path to append to the base path of the client. The URL can
     * contain the query string as well. Use an dict<arraykey,  mixed> to provide a URL
     * template and additional variables to use in the URL template expansion.
     *
     * @param mixed $uri     URI object or string.
     * @param dict<arraykey,  mixed>               $options Request options to apply.
     */
    public function patchAsync(mixed $uri, dict<arraykey,  mixed> $options = dict[]): PromiseInterface
    {
        return $this->requestAsync('PATCH', $uri, $options);
    }

    /**
     * Create and send an asynchronous HTTP DELETE request.
     *
     * Use an absolute path to override the base path of the client, or a
     * relative path to append to the base path of the client. The URL can
     * contain the query string as well. Use an dict<arraykey,  mixed> to provide a URL
     * template and additional variables to use in the URL template expansion.
     *
     * @param mixed $uri     URI object or string.
     * @param dict<arraykey,  mixed>               $options Request options to apply.
     */
    public function deleteAsync(mixed $uri, dict<arraykey,  mixed> $options = dict[]): PromiseInterface
    {
        return $this->requestAsync('DELETE', $uri, $options);
    }
}
