/**
 * @presideService
 */
component singleton=true {

	variables.ipLookupCache = {};

// CONSTRUCTOR
	/**
	 * @systemConfigurationService.inject systemConfigurationService
	 * @logger.inject                     logbox:logger:ip-geolocation
	 */
	public any function init( required any systemConfigurationService, required any logger ) {
		_setSystemConfigurationService( arguments.systemConfigurationService );
		_setLogger( arguments.logger );

		return this;
	}

// PUBLIC API METHODS
	public any function getIP( required string ipAddress, struct additionalParams={} ) {
		var apiKey   = _getApiKey();
		var uri      = _getResultFormat() & "/" & arguments.ipAddress;
		var endpoint = _getEndpoint();

		if( !( left( endpoint, 1 ) == "/") ) {
			uri = "/" & uri;
		}

		var queryStringSeparator = "?";
		var cachedResult         = getIpLookupFromCache( arguments.ipAddress );

		if( !structIsEmpty( cachedResult ) ){
			return cachedResult;
		}

		if( _getCallbackMethod().Len() ) {
			if( !_getCallbackKey().Len() ) {
				_processError( "missingConfig", "You must set the callback Key AND method in the CMS Settings when using the callback feature." );
			}
			uri &= queryStringSeparator & _getCallbackKey() & "=" & _getCallbackMethod()
			queryStringSeparator = "&";
		}

		for ( var key in additionalParams ) {
			uri &= queryStringSeparator & key & "=" & additionalParams[ key ];
			queryStringSeparator = "&";
		}

		if( Len( Trim( apiKey ) ) ){
			uri &= queryStringSeparator & "key=" & apiKey;
		}

		return _sendRequest( uri );
	}

	public struct function getIpLookupFromCache( required string ipAddress ) {
		if ( !ipLookupCache.keyExists( arguments.ipAddress ) ) {
			return {};
		}

		return ipLookupCache[ arguments.ipAddress ];
	}

	public struct function scaffoldBlankResponse() {
		return {
			  businessName    = ""
			, businessWebsite = ""
			, city            = "London"
			, continent       = "Europe"
			, country         = "United Kingdom"
			, countryCode     = "GB"
			, ipName          = ""
			, ipType          = ""
			, isp             = ""
			, lat             = "0.0"
			, lon             = "0.0"
			, org             = ""
			, query           = "86.187.167.123"
			, region          = "London, City of"
			, status          = "bypassed"
		};
	}


// PRIVATE HELPERS
	private any function _sendRequest( required string uri, string method="GET", string body="" ) {
		var result         = "";
		var fullUrl        = _getEndpoint() & arguments.uri;
		var requestTimeout = _getApiCallTimeout();
		var apiKey         = _getApiKey();

		try {
			http method=arguments.method url=fullUrl result="result" timeout=requestTimeout {
				if ( Len( Trim( apiKey ) ) ) {
					httpparam type="url" name="auth" value=apiKey;
				}
				if ( Len( Trim( arguments.body ) ) ) {
					httpparam type="body" value=arguments.body;
				}
			}
		} catch ( any e ) {
			$raiseError( e );
			return "Message: " & ( e.message ?: "" )  & " Detail: " & ( e.detail ?: "" );
		}

		return _processHttpResponse( result, arguments.method, arguments.uri, arguments.body );
	}

	private boolean function _isSuccessfulResponse( required struct httpResponse) {
		var statusCode  = arguments.httpResponse.responseheader.status_code ?: "";
		var fileContent = arguments.httpResponse.fileContent                ?: "";

		return statusCode == "200" && Len( Trim( fileContent ) );
	}

	private any function _processHttpResponse( required struct httpResponse, required string method, required string uri, required string body ) {
		if ( _isSuccessfulResponse( arguments.httpResponse ) ) {
			var response          = {};
			var format            = _getResultFormat();
			var hasCallbackMethod = ( _getCallbackMethod().Len() > 0 );

			try {
				if( format == "json" && !hasCallbackMethod ) {
					response = DeserializeJson( arguments.httpResponse.filecontent );
				} else if ( format == "json" && hasCallbackMethod ) {
					response = ( toString( toBinary( arguments.httpResponse.filecontent ) ) );
				} else if ( format == "xml" ) {
					response = XMLParse( arguments.httpResponse.filecontent );
				} else {
					response = arguments.httpResponse.filecontent;
				}
			} catch( any e ) {
				_processError( "invalid.response", "Expected " & UCase( format ) &  " response but received, [" & arguments.httpResponse.filecontent & "].", arguments.httpResponse );
			}

			if ( ( response.status ?: "" ) == "success" || ( isSimpleValue( response ) && findNoCase( "success", response ) ) ) {
				ipLookupCache[ response.query ?: "unknown" ] = response;
				return response;
			} else {
				if ( Len( Trim( response.message ?: "" ) ) ) {
					_processError( "error.response", "Error processing IP Geolocation " & arguments.method & " request. Failure reason: [" & response.message & "]. Method URI: [" & arguments.uri & "]. Method body: [" & arguments.body & "]", arguments.httpResponse );
				} else {
					_processError( "invalid.response", "Expected " & UCase( format ) & " response but received, [" & httpResponse.fileContent & "].", arguments.httpResponse );
				}
			}
		} else {
			if ( arguments.httpResponse.keyExists( "message" ) ) {
				_processError( "error.response", "Error processing IP Geolocation " & arguments.method & " request. Failure reason: [" & arguments.httpResponse.message & "].", arguments.httpResponse );
			} else {
				_processError( "invalid.response", "Expected json response but received an unexpected response from the server.", arguments.httpResponse );
			}
		}
	}

	private void function _processError( required string errorType, required string message, struct extraInfo={}, throwError=true ) {
		var logger = _getLogger();

		if ( logger.canError() ) {
			_getLogger().error( arguments.message, arguments.extraInfo );
		}
		if( arguments.throwError ){
			throw( type="IpLookupWrapper.#arguments.errorType#", message=arguments.message, detail=SerializeJson( arguments.extraInfo ) );
		}
	}


// GETTERS AND SETTERS
	private any function _getSystemConfigurationService() {
		return _systemConfigurationService;
	}
	private void function _setSystemConfigurationService( required any systemConfigurationService ) {
		_systemConfigurationService = arguments.systemConfigurationService;
	}

	private any function _getLogger() {
		return _logger;
	}
	private void function _setLogger( required any logger ) {
		_logger = arguments.logger;
	}

	private string function _getEndpoint() {
		return _getSystemConfigurationService().getSetting( "ip_geolocation", "endpoint", "" );
	}

	private string function _getResultFormat() {
		var resultFormat = _getSystemConfigurationService().getSetting( "ip_geolocation", "result_format", "json" );
		return resultFormat.len() ? resultFormat : "json";
	}

	private string function _getCallbackKey() {
		return _getSystemConfigurationService().getSetting( "ip_geolocation", "callback_key", "" );
	}

	private string function _getCallbackMethod() {
		return _getSystemConfigurationService().getSetting( "ip_geolocation", "callback_method", "" );
	}

	private string function _getApiKey() {
		return _getSystemConfigurationService().getSetting( "ip_geolocation", "api_key", "" );
	}

	private numeric function _getApiCallTimeout() {
		return Val( _getSystemConfigurationService().getSetting( "ip_geolocation", "api_call_timeout", "5" ) );
	}

}