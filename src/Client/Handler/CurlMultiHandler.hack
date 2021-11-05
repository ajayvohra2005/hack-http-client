namespace HackHttp\Client\Handler;

use namespace HackPromises as P;
use HackPromises\Promise;
use HackPromises\PromiseInterface;
use HackHttp\Client\Utils;
use HackHttp\Message\RequestInterface;

use namespace HH;
use namespace HH\Lib\C;
use namespace HH\Lib\Math;

type CurlHandleEntry = shape( "easy" => EasyHandle, "deferred" => PromiseInterface, "time" => float );

/**
 * Returns an asynchronous response using curl_multi_* functions.
 *
 * When using the CurlMultiHandler, custom curl options can be specified as an
 * associative array of curl option constants mapping to values in the
 * **curl** key of the provided request options.
 *
 * @final
 */
final class CurlMultiHandler
{
    /**
     * @var CurlFactoryInterface
     */
    private CurlFactoryInterface $factory;

    /**
     * @var float
     */
    private float $selectTimeout = 1.0;

     /**
     * @var ?resource multi-handle resource
     */
    private ?resource $_mh;

    /**
     * @var mixed the currently executing resource in `curl_multi_exec`.
     */
    private mixed $active;

    /**
     * @var Vector<CurlHandle> Request  handle entries
     *
     */
    private Vector<CurlHandleEntry> $entries;

     /**
     * @var int $ndelayed  Number of handle entries delayed
     *
     */
     private int $ndelayed = 0;

    /**
     * This handler accepts the following options:
     *
     * - handle_factory: An optional factory  used to create curl handles
     * - select_timeout: Optional timeout (in seconds) to block before timing
     *   out while selecting curl handles. Defaults to 1 second.
     */
    public function __construct(dict<arraykey, mixed> $options = dict[])
    {
        $this->entries = new Vector<CurlHandleEntry>(vec[]);

        $options_handle_factory = HH\idx($options, 'handle_factory');
        if($options_handle_factory is CurlFactoryInterface) {
            $this->factory = $options_handle_factory;
        } else {
            $this->factory = new CurlFactory();
        }

        $options_select_timeout = HH\idx($options, 'select_timeout');
        if ($options_select_timeout is num) {
            $this->selectTimeout = (float)$options_select_timeout;
        } 

        $this->init();

    }

    private function init(): ?resource
    {
        $multiHandle = \curl_multi_init();

        if ($multiHandle is resource) {
            $this->_mh = $multiHandle;
        } else {
            throw new \RuntimeException('Could not initialize curl multi handle.');
        }

        $this->closeOnShutdown();
        
        return $this->_mh;
    }

    private function closeOnShutdown(): void
    {
        \register_shutdown_function(() ==> {
            if ($this->_mh is resource) {
                \curl_multi_close($this->_mh);
            }
        });
        
    }

    public function handle(RequestInterface $request, dict<arraykey, mixed> $options): PromiseInterface
    {
        $easy = $this->factory->create($request, $options);

        $wait_cb = (P\ResolveCallback $rcb): void ==> {
            $this->execute();
        };

        $cancel_cb = (P\RejectCallback $rcb): void ==> {
            $this->cancel($easy->getHandle());
        };

        $promise = new Promise($wait_cb, $cancel_cb);
        $this->addRequest(shape('easy' => $easy, 'deferred' => $promise, 'time' => 0.0));

        return $promise;
    }

    /**
     * Ticks the curl event loop.
     */
    public function tick(): void
    {
        // Add any delayed handles if needed.
        $mh = $this->_mh;

        if(!($mh is resource)) {
            throw new \RuntimeException("Multi handle is not a resource");
        }

        if ($this->ndelayed) {
            $currentTime = Utils::currentTime();
            foreach ($this->entries as $key => $entry) {
                if ($currentTime >= $entry["time"]) {
                    $this->entries[$key]["time"] = 0.0;
                    $this->ndelayed -= 1;
                    $ch = $entry['easy']->getHandle();
                    if($ch is resource) {
                        \curl_multi_add_handle($mh,$ch);
                    } else {
                        throw new \RuntimeException("Curl handle is not a resource");
                    }
                }
            }
        }

        // Step through the task queue which may add additional requests.
        P\TaskQueue::globalTaskQueue()->run();

        if ($this->active  && \curl_multi_select($mh, $this->selectTimeout) === -1) {
            \usleep(250);
        }

        $_active = $this->active;
        while (\curl_multi_exec($mh, inout $_active) === \CURLM_CALL_MULTI_PERFORM);
        $this->active = $_active;

        $this->processMessages();
    }

    /**
     * Runs until all outstanding connections have completed.
     */
    public function execute(): void
    {
        $queue = P\TaskQueue::globalTaskQueue();

        while ($this->entries || !$queue->isEmpty()) {
            // If there are no transfers, then sleep for the next delay
            if ($this->active is null && $this->ndelayed) {
                \usleep($this->timeToNext());
            }
            $this->tick();
        }
    }

    private function addRequest(CurlHandleEntry $entry): void
    {
        $mh = $this->_mh;
        if(!($mh is resource)) {
            throw new \RuntimeException("Multihandle is not a resource");
        }

        $easy = $entry['easy'];
        if ($easy->delay() > 0.0) {
            $entry['time'] =  (Utils::currentTime() + ($easy->delay() / 1000));
            $this->ndelayed += 1;
        } else {
            $ch = $easy->getHandle();
            if($ch is resource) {
                \curl_multi_add_handle($mh, $ch);
            } else {
                throw new \RuntimeException("Curl handle are not a resource");
            }
            $entry['time'] = 0.0;
        }

        $this->entries[] = $entry;
    }

    private function findEntryKey(resource $handle): ?int 
    {
        $find_pred = (CurlHandleEntry $entry): bool ==> $entry["easy"]->getHandle() === $handle;
        return C\find_key($this->entries, $find_pred); 
    }

    /**
     * Cancels a handle from sending and removes references to it, if the handle has not
     * already been processed.
     *
     * @param resource $resource curl handle resource to remove
     *
     * @return bool True on success, false on failure.
     */
    private function cancel(?resource $handle): bool
    {
        if($handle is resource) {
            $entry_key = $this->findEntryKey($handle);

            if ($entry_key is nonnull && $this->_mh is resource && $handle is resource) {
                \curl_multi_remove_handle($this->_mh, $handle);
                \curl_close($handle);
                if($this->entries[$entry_key]['time'] > 0) {
                    $this->ndelayed -= 1;
                }
                $this->entries->removeKey($entry_key);
                return true;
            }
        }

        return false;
    }

    private function processMessages(): void
    {
        $mh = $this->_mh;

        if(!($mh is resource)) {
            throw new \RuntimeException("Multi handle is not a resource");
        }

        $queued_messages = null;

        while (true) {
            $ret = \curl_multi_info_read($mh, inout $queued_messages);

            if($ret === false) {
                break;
            }

            $ch = $ret['handle'];
            \curl_multi_remove_handle($mh, $ch);

            $entry_key = $this->findEntryKey($ch);
            
            if($entry_key is nonnull) {
                $entry = $this->entries[$entry_key];  
                $this->entries->removeKey($entry_key);

                $entry['easy']->setErrno($ret['result']);
                $callable = (RequestInterface $request, dict<arraykey, mixed> $options): PromiseInterface ==> {
                    return $this->handle($request, $options);
                };
                $entry['deferred']->resolve(CurlFactory::finish($callable, $entry['easy'], $this->factory));
            }
        }
    }

    private function timeToNext(): int
    {
        $currentTime = Utils::currentTime();
        $nextTime = Math\INT64_MAX;
        foreach ($this->entries as $entry) {
            $time = $entry['time'];
            if ($time > 0 && $time < $nextTime) {
                $nextTime = $time;
            }
        }

        return \min(((int) \max(0, $nextTime - $currentTime)) * 1000000, 1000000);
    }
}
