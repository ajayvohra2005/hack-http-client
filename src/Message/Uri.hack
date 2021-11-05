namespace HackHttp\Message;

use namespace HH;
use HH\Lib\Str;

/**
 * HTTP URI implementation.
 */
class Uri implements UriInterface
{
    const string HTTP_DEFAULT_HOST = 'localhost';
    const dict<string, int> DEFAULT_PORTS = dict[
        "http" => 80,
        "https" => 443,
        'ftp' => 21,
        'gopher' => 70,
        'nntp' => 119,
        'news' => 119,
        'telnet' => 23,
        'tn3270' => 23,
        'imap' => 143,
        'pop' => 110,
        'ldap' => 389,
    ];

    /**
     * Unreserved characters for use in a regex.
     *
     * @link https://tools.ietf.org/html/rfc3986#section-2.3
     */
    const string CHAR_UNRESERVED = 'a-zA-Z0-9_\-\.~';

    /**
     * Sub-delims for use in a regex.
     *
     * @link https://tools.ietf.org/html/rfc3986#section-2.2
     */
    const string CHAR_SUB_DELIMS = '!\$&\'\(\)\*\+,;=';
    const dict<string, string> QUERY_SEPARATORS_REPLACEMENT = dict['=' => '%3D', '&' => '%26'];

    /** @var string Uri scheme. */
    private string $scheme = '';

    /** @var string Uri user info. */
    private string $userInfo = '';

    /** @var string Uri host. */
    private string $host = '';

    /** @var int|null Uri port. */
    private ?int $port;

    /** @var string Uri path. */
    private string $path = '';

    /** @var string Uri query string. */
    private string $query = '';

    /** @var string Uri fragment. */
    private string $fragment = '';

    /** @var string|null String representation */
    private ?string $composedComponents;

    public function __construct(string $uri = '')
    {
        if ($uri !== '') {
            $parts = self::parse($uri);
            if ($parts is null) {
                throw new MalformedUriException("Unable to parse URI: $uri");
            }
            $this->applyParts($parts);
        }
    }
    /**
     * UTF-8 aware \parse_url() replacement.
     *
     * The internal function produces broken output for non ASCII domain names
     * (IDN) when used with locales other than "C".
     *
     * On the other hand, cURL understands IDN correctly only when UTF-8 locale
     * is configured ("C.UTF-8", "en_US.UTF-8", etc.).
     *
     * @see https://bugs.php.net/bug.php?id=52923
     * @see https://www.php.net/manual/en/function.parse-url.php#114817
     * @see https://curl.haxx.se/libcurl/c/CURLOPT_URL.html#ENCODING
     *
     * @return array|false
     */
    private static function parse(string $url): ?dict<string, mixed>
    {
        // If IPv6
        $prefix = '';
        $matches = vec<string>[];
        if (\preg_match_with_matches('%^(.*://\[[0-9:a-f]+\])(.*?)$%', $url, inout $matches)) {
            /** @var array{0:string, 1:string, 2:string} $matches */
            $prefix = $matches[1];
            $url = $matches[2];
        }

        /** @var string */
        $match_cb = (mixed $m): string ==> {
            if(HH\is_any_array($m)) {
                $m = vec($m);
                $m = Utils::filterTraversable<string>($m);
                return \urlencode($m[0]);
            }

            return '';
        };

        $count = 0;
        $encodedUrl = \preg_replace_callback('%[^:/@?&=#]+%usD', $match_cb, $url, -1, inout $count);

        $result = \parse_url($prefix . $encodedUrl);

        if ($result === false) {
            return null;
        }

        $decocde_cb = (mixed $u) ==> {
            if(Utils::is_implicit_string($u)) {
                return \urldecode((string)$u);
            }

            return '';
        };

        $container = \array_map($decocde_cb, $result);
        return Utils::filterDictStringKeys($container);
    }

    public function __toString(): string
    {
        if ($this->composedComponents === null) {
            $this->composedComponents = self::composeComponents(
                $this->scheme,
                $this->getAuthority(),
                $this->path,
                $this->query,
                $this->fragment
            );
        }

        return $this->composedComponents;
    }

    /**
     * Composes a URI reference string from its various components.
     *
     * @link https://tools.ietf.org/html/rfc3986#section-5.3
     */
    public static function composeComponents(?string $scheme, ?string $authority, string $path, ?string $query, ?string $fragment): string
    {
        $uri = '';

        // weak type checks to also accept null until we can add scalar type hints
        if ($scheme != '') {
            $uri .= $scheme . ':';
        }

        if ($authority != ''|| $scheme === 'file') {
            $uri .= '//' . $authority;
        }

        $uri .= $path;

        if ($query != '') {
            $uri .= '?' . $query;
        }

        if ($fragment != '') {
            $uri .= '#' . $fragment;
        }

        return $uri;
    }

    /**
     * Whether the URI has the default port of the current scheme.
     *
     * `Psr\HackHttp\Message\UriInterface::getPort` may return null or the standard port. This method can be used
     * independently of the implementation.
     */
    public static function isDefaultPort(UriInterface $uri): bool
    {
        return $uri->getPort() === null
            || (isset(self::DEFAULT_PORTS[$uri->getScheme()]) && $uri->getPort() === self::DEFAULT_PORTS[$uri->getScheme()]);
    }

    /**
     * Whether the URI is absolute, i.e. it has a scheme.
     *
     * An instance of UriInterface can either be an absolute URI or a relative reference. This method returns true
     * if it is the former. An absolute URI has a scheme. A relative reference is used to express a URI relative
     * to another URI, the base URI. Relative references can be divided into several forms:
     * - network-path references, e.g. '//example.com/path'
     * - absolute-path references, e.g. '/path'
     * - relative-path references, e.g. 'subpath'
     *
     * @see Uri::isNetworkPathReference
     * @see Uri::isAbsolutePathReference
     * @see Uri::isRelativePathReference
     * @link https://tools.ietf.org/html/rfc3986#section-4
     */
    public static function isAbsolute(UriInterface $uri): bool
    {
        return $uri->getScheme() !== '';
    }

    /**
     * Whether the URI is a network-path reference.
     *
     * A relative reference that begins with two slash characters is termed an network-path reference.
     *
     * @link https://tools.ietf.org/html/rfc3986#section-4.2
     */
    public static function isNetworkPathReference(UriInterface $uri): bool
    {
        return $uri->getScheme() === '' && $uri->getAuthority() !== '';
    }

    /**
     * Whether the URI is a absolute-path reference.
     *
     * A relative reference that begins with a single slash character is termed an absolute-path reference.
     *
     * @link https://tools.ietf.org/html/rfc3986#section-4.2
     */
    public static function isAbsolutePathReference(UriInterface $uri): bool
    {
        return $uri->getScheme() === ''
            && $uri->getAuthority() === ''
            && isset($uri->getPath()[0])
            && $uri->getPath()[0] === '/';
    }

    /**
     * Whether the URI is a relative-path reference.
     *
     * A relative reference that does not begin with a slash character is termed a relative-path reference.
     *
     * @link https://tools.ietf.org/html/rfc3986#section-4.2
     */
    public static function isRelativePathReference(UriInterface $uri): bool
    {
        return $uri->getScheme() === ''
            && $uri->getAuthority() === ''
            && (!isset($uri->getPath()[0]) || $uri->getPath()[0] !== '/');
    }

    /**
     * Whether the URI is a same-document reference.
     *
     * A same-document reference refers to a URI that is, aside from its fragment
     * component, identical to the base URI. When no base URI is given, only an empty
     * URI reference (apart from its fragment) is considered a same-document reference.
     *
     * @param UriInterface      $uri  The URI to check
     * @param UriInterface|null $base An optional base URI to compare against
     *
     * @link https://tools.ietf.org/html/rfc3986#section-4.4
     */
    public static function isSameDocumentReference(UriInterface $uri, ?UriInterface $base = null): bool
    {
        if ($base !== null) {
            $uri = UriResolver::resolve($base, $uri);

            return ($uri->getScheme() === $base->getScheme())
                && ($uri->getAuthority() === $base->getAuthority())
                && ($uri->getPath() === $base->getPath())
                && ($uri->getQuery() === $base->getQuery());
        }

        return $uri->getScheme() === '' && $uri->getAuthority() === '' && $uri->getPath() === '' && $uri->getQuery() === '';
    }

    /**
     * Creates a new URI with a specific query string value removed.
     *
     * Any existing query string values that exactly match the provided key are
     * removed.
     *
     * @param UriInterface $uri URI to use as a base.
     * @param string       $key Query string key to remove.
     */
    public static function withoutQueryValue(UriInterface $uri, string $key): UriInterface
    {
        $result = self::getFilteredQueryString($uri, vec[$key]);

        return $uri->withQuery(\implode('&', $result));
    }

    /**
     * Creates a new URI with a specific query string value.
     *
     * Any existing query string values that exactly match the provided key are
     * removed and replaced with the given key value pair.
     *
     * A value of null will set the query string key without a value, e.g. "key"
     * instead of "key=value".
     *
     * @param UriInterface $uri   URI to use as a base.
     * @param string       $key   Key to set.
     * @param string|null  $value Value to set
     */
    public static function withQueryValue(UriInterface $uri, string $key, ?string $value): UriInterface
    {
        $result = self::getFilteredQueryString($uri, vec[$key]);

        $result[] = self::generateQueryString($key, $value);

        return $uri->withQuery(\implode('&', $result));
    }

    /**
     * Creates a new URI with multiple specific query string values.
     *
     * It has the same behavior as withQueryValue() but for an associative array of key => value.
     *
     * @param UriInterface               $uri           URI to use as a base.
     * @param dict<string, mixed> $keyValueArray Associative array of key and values
     */
    public static function withQueryValues(UriInterface $uri, dict<string, mixed> $keyValueArray): UriInterface
    {
        $result = self::getFilteredQueryString($uri, \array_keys($keyValueArray));

        foreach ($keyValueArray as $key => $value) {
            $result[] = self::generateQueryString((string) $key, $value !== null ? (string) $value : null);
        }

        return $uri->withQuery(\implode('&', $result));
    }

    /**
     * Creates a URI from a hash of `parse_url` components.
     *
     * @link http://php.net/manual/en/function.parse-url.php
     *
     * @throws MalformedUriException If the components do not form a valid URI.
     */
    public static function fromParts(dict<string, mixed> $parts): UriInterface
    {
        $uri = new self();
        $uri->applyParts($parts);
        $uri->validateState();

        return $uri;
    }

    public function getScheme(): string
    {
        return $this->scheme;
    }

    public function getAuthority(): string
    {
        $authority = $this->host;
        if ($this->userInfo !== '') {
            $authority = $this->userInfo . '@' . $authority;
        }

        if ($this->port !== null) {
            $authority .= ':' . $this->port;
        }

        return $authority;
    }

    public function getUserInfo(): string
    {
        return $this->userInfo;
    }

    public function getHost(): string
    {
        return $this->host;
    }

    public function getPort(): ?int
    {
        return $this->port;
    }

    public function getPath(): string
    {
        return $this->path;
    }

    public function getQuery(): string
    {
        return $this->query;
    }

    public function getFragment(): string
    {
        return $this->fragment;
    }

    public function withScheme(string $scheme): UriInterface
    {
        $scheme = $this->filterScheme($scheme);

        if ($this->scheme === $scheme) {
            return $this;
        }

        $new = clone $this;
        $new->scheme = $scheme;
        $new->composedComponents = null;
        $new->removeDefaultPort();
        $new->validateState();

        return $new;
    }

    public function withUserInfo(string $user, ?string $password = null): UriInterface
    {
        $info = $this->filterUserInfoComponent($user);
        if ($password !== null) {
            $info .= ':' . $this->filterUserInfoComponent($password);
        }

        if ($this->userInfo === $info) {
            return $this;
        }

        $new = clone $this;
        $new->userInfo = $info;
        $new->composedComponents = null;
        $new->validateState();

        return $new;
    }

    public function withHost(string $host): UriInterface
    {
        $host = $this->filterHost($host);

        if ($this->host === $host) {
            return $this;
        }

        $new = clone $this;
        $new->host = $host;
        $new->composedComponents = null;
        $new->validateState();

        return $new;
    }

    public function withPort(?int $port=null): UriInterface
    {
        $port = $this->filterPort($port);

        if ($this->port === $port) {
            return $this;
        }

        $new = clone $this;
        $new->port = $port;
        $new->composedComponents = null;
        $new->removeDefaultPort();
        $new->validateState();

        return $new;
    }

    public function withPath(string $path): UriInterface
    {
        $path = $this->filterPath($path);

        if ($this->path === $path) {
            return $this;
        }

        $new = clone $this;
        $new->path = $path;
        $new->composedComponents = null;
        $new->validateState();

        return $new;
    }

    public function withQuery(string $query): UriInterface
    {
        $query = $this->filterQueryAndFragment($query);

        if ($this->query === $query) {
            return $this;
        }

        $new = clone $this;
        $new->query = $query;
        $new->composedComponents = null;

        return $new;
    }

    public function withFragment(string $fragment): UriInterface
    {
        $fragment = $this->filterQueryAndFragment($fragment);

        if ($this->fragment === $fragment) {
            return $this;
        }

        $new = clone $this;
        $new->fragment = $fragment;
        $new->composedComponents = null;

        return $new;
    }

    /**
     * Apply parse_url parts to a URI.
     *
     * @param array $parts Array of parse_url parts to apply.
     */
    private function applyParts(dict<string, mixed> $parts): void
    {
        $this->scheme = isset($parts['scheme'])
            ? $this->filterScheme($parts['scheme'])
            : '';
        $this->userInfo = isset($parts['user'])
            ? $this->filterUserInfoComponent($parts['user'])
            : '';
        $this->host = isset($parts['host'])
            ? $this->filterHost($parts['host'])
            : '';
        $this->port = isset($parts['port'])
            ? $this->filterPort($parts['port'])
            : null;
        $this->path = isset($parts['path'])
            ? $this->filterPath($parts['path'])
            : '';
        $this->query = isset($parts['query'])
            ? $this->filterQueryAndFragment($parts['query'])
            : '';
        $this->fragment = isset($parts['fragment'])
            ? $this->filterQueryAndFragment($parts['fragment'])
            : '';
        if (isset($parts['pass'])) {
            $this->userInfo .= ':' . $this->filterUserInfoComponent($parts['pass']);
        }

        $this->removeDefaultPort();
    }

    /**
     * @param mixed $scheme
     *
     * @throws \InvalidArgumentException If the scheme is invalid.
     */
    private function filterScheme(mixed $scheme): string
    {
        if (!($scheme is string)) {
            throw new \InvalidArgumentException('Scheme must be a string');
        }

        return \strtr($scheme, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz');
    }

    /**
     * @param mixed $component
     *
     * @throws \InvalidArgumentException If the user info is invalid.
     */
    private function filterUserInfoComponent(mixed $component): string
    {
        if (!($component is string)) {
            throw new \InvalidArgumentException('User info must be a string');
        }

        $count = 0;
        $cb = (mixed $v): string ==> {

            if(HH\is_any_array($v)) {
                $v = vec($v);
                $v = Utils::filterTraversable<string>($v);
                return $this->rawurlencodeMatchZero($v);
            }

            return '';
        };

        return \preg_replace_callback(
            '/(?:[^%' . self::CHAR_UNRESERVED . self::CHAR_SUB_DELIMS . ']+|%(?![A-Fa-f0-9]{2}))/',
            $cb, $component, -1, inout $count);
    }

    /**
     * @param mixed $host
     *
     * @throws \InvalidArgumentException If the host is invalid.
     */
    private function filterHost(mixed $host): string
    {
        if (!($host is string)) {
            throw new \InvalidArgumentException('Host must be a string');
        }

        return \strtr($host, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz');
    }

    /**
     * @param mixed $port
     *
     * @throws \InvalidArgumentException If the port is invalid.
     */
    private function filterPort(mixed $port): ?int
    {
        if ($port === null) {
            return null;
        }

        $port = (int) $port;
        if (0 > $port || 0xffff < $port) {
            throw new \InvalidArgumentException(
                \sprintf('Invalid port: %d. Must be between 0 and 65535', $port)
            );
        }

        return $port;
    }

    /**
     * @param vec<string> $keys
     *
     * @return vec<string>
     */
    private static function getFilteredQueryString(UriInterface $uri, vec<string> $keys): vec<string>
    {
        $current = $uri->getQuery();

        if ($current === '') {
            return vec[];
        }

        $rawurldecode_cb = ($v) ==> \rawurldecode($v);

        $decodedKeys = \array_map($rawurldecode_cb, $keys);
        $in_array_cb = ($part) ==> !\in_array(\rawurldecode(\explode('=', $part)[0]), $decodedKeys, true);
        return vec(\array_filter(\explode('&', $current), $in_array_cb));
    }

    private static function generateQueryString(string $key, ?string $value): string
    {
        // Query string separators ("=", "&") within the key or value need to be encoded
        // (while preventing double-encoding) before setting the query string. All other
        // chars that need percent-encoding will be encoded by withQuery().
        $queryString = \strtr($key, self::QUERY_SEPARATORS_REPLACEMENT);

        if ($value !== null) {
            $queryString .= '=' . \strtr($value, self::QUERY_SEPARATORS_REPLACEMENT);
        }

        return $queryString;
    }

    private function removeDefaultPort(): void
    {
        if ($this->port !== null && self::isDefaultPort($this)) {
            $this->port = null;
        }
    }

    /**
     * Filters the path of a URI
     *
     * @param mixed $path
     *
     * @throws \InvalidArgumentException If the path is invalid.
     */
    private function filterPath(mixed $path): string
    {
        if (!($path is string)) {
            throw new \InvalidArgumentException('Path must be a string');
        }

        $count = 0;
        $cb = (mixed $v): string ==> {

            if(HH\is_any_array($v)) {
                $v = vec($v);
                $v = Utils::filterTraversable<string>($v);
                return $this->rawurlencodeMatchZero($v);
            }

            return '';
        };

        return \preg_replace_callback(
            '/(?:[^' . self::CHAR_UNRESERVED . self::CHAR_SUB_DELIMS . '%:@\/]++|%(?![A-Fa-f0-9]{2}))/',
            $cb, $path, -1, inout $count);
    }

    /**
     * Filters the query string or fragment of a URI.
     *
     * @param mixed $str
     *
     * @throws \InvalidArgumentException If the query or fragment is invalid.
     */
    private function filterQueryAndFragment(mixed $str): string
    {
        if (!($str is string)) {
            throw new \InvalidArgumentException('Query and fragment must be a string');
        }

        $count = 0;
        $cb = (mixed $v): string ==> {

            if(HH\is_any_array($v)) {
                $v = vec($v);
                $v = Utils::filterTraversable<string>($v);
                return $this->rawurlencodeMatchZero($v);
            }

            return '';
        };
        
        return \preg_replace_callback(
            '/(?:[^' . self::CHAR_UNRESERVED . self::CHAR_SUB_DELIMS . '%:@\/\?]++|%(?![A-Fa-f0-9]{2}))/',
            $cb, $str, -1, inout $count);


    }

    private function rawurlencodeMatchZero(vec<string> $match): string
    {
        return \rawurlencode($match[0]);
    }

    private function validateState(): void
    {
        if ($this->host === '' && ($this->scheme === 'http' || $this->scheme === 'https')) {
            $this->host = self::HTTP_DEFAULT_HOST;
        }

        if ($this->getAuthority() === '') {
            if (0 === Str\search($this->path, '//')) {
                throw new MalformedUriException('The path of a URI without an authority must not start with two slashes "//"');
            }
            if ($this->scheme === '' && Str\search(\explode('/', $this->path, 2)[0], ':') is int) {
                throw new MalformedUriException('A relative URI must not have a path beginning with a segment containing a colon');
            }
        } elseif (isset($this->path[0]) && $this->path[0] !== '/') {
            throw new MalformedUriException('The path of a URI with an authority must start with a slash "/" or be empty');
        }
    }
}
