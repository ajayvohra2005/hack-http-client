namespace HackHttp\Client\Cookie;

use HackHttp\Client\Utils;

/**
 * Persists non-session cookies using a JSON formatted file
 */
class FileCookieJar extends CookieJar
{
    /**
     * @var string filename
     */
    private string $filename;

    /**
     * @var bool Control whether to persist session cookies or not.
     */
    private bool $storeSessionCookies;

    /**
     * Create a new FileCookieJar object
     *
     * @param string $cookieFile          File to store the cookie data
     * @param bool   $storeSessionCookies Set to true to store session cookies
     *                                    in the cookie jar.
     *
     * @throws \RuntimeException if the file cannot be found or created
     */
    public function __construct(string $cookieFile, bool $storeSessionCookies = false)
    {
        parent::__construct();
        $this->filename = $cookieFile;
        $this->storeSessionCookies = $storeSessionCookies;

        if (\file_exists($cookieFile)) {
            $this->load($cookieFile);
        }

        $this->saveOnShutdown();
    }

    private function saveOnShutdown(): void
    {
        \register_shutdown_function(() ==> {
            $this->save();
        });
        
    }

    /**
     * Saves the cookies to a file.
     *
     * @param string $filename File to save
     *
     * @throws \RuntimeException if the file cannot be found or created
     */
    public function save(?string $filename=null): void
    {
        if($filename is null) {
            $filename = $this->filename;
        }
        $json = vec[];
        /** @var SetCookie $cookie */
        foreach ($this as $cookie) {
            if (CookieJar::shouldPersist($cookie, $this->storeSessionCookies)) {
                $json[] = $cookie->toArray();
            }
        }

        $jsonStr = Utils::jsonEncode($json);
        if (false === \file_put_contents($filename, $jsonStr, \LOCK_EX)) {
            throw new \RuntimeException("Unable to save file {$filename}");
        }
    }

    /**
     * Load cookies from a JSON formatted file.
     *
     * Old cookies are kept unless overwritten by newly loaded ones.
     *
     * @param string $filename Cookie file to load.
     *
     * @throws \RuntimeException if the file cannot be loaded.
     */
    public function load(string $filename): void
    {
        $json = \file_get_contents($filename);
        if (false === $json) {
            throw new \RuntimeException("Unable to load file {$filename}");
        }
        if ($json === '') {
            return;
        }

        $data = Utils::jsonDecode($json, true);
        if ($data is Traversable<_>) {
            foreach ($data as $cookie) {
                if($cookie is dict<_,_>) {
                    $this->setCookie(new SetCookie($cookie));
                }
            }
        } elseif (\is_scalar($data) && !$data) {
            throw new \RuntimeException("Invalid cookie file: {$filename}");
        }
    }
}
