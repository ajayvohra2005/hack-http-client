namespace HackHttp\Client;

/**
 * Thrown when the request cannot be completed because of network issues.
 *
 * There is no response object as this exception is thrown when no response has been received.
 *
 * Example: the target host name can not be resolved or the connection failed.
 */
abstract class AbstractNetworkException extends AbstractRequestException
{
   
}
