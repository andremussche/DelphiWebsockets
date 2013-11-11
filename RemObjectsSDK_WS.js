//*************************************************************//   
//some extra stuff for Websockets PoC
//by: André Mussche, andre.mussche@gmail.com
   
function WebSocketsWrapper(url, aWebSocketClientChannel) {
    this.updating = false;
    this.urlCall = url;
    this.WebSocketClientChannel = aWebSocketClientChannel; 
};

WebSocketsWrapper.prototype.post = function post(passData, isBinary, onSuccessFunction, onErrorFunction) 
{
    //if (this.updating) {
    //    return false;
    //};
    this.WS = this.WS || null;
    if (this.WS) {
      if (this.updating) {
        return false;
      }
      if (this.WS.readyState == 2 ||  //CLOSING
          this.WS.readyState == 3)    //CLOSED
        this.WS = null; 
    };
    
    var parser = new BinaryParser();                  

    //check websocket support
    if ("WebSocket" in window) 
    {
        if (isBinary == true)
        {
            //add messagenr to end
            var sMsgNr = 'WSNR' + parser.encodeInt(12345, 32, false);
            passData = passData + sMsgNr;
            
            var len  = passData.length;
            var data = new Uint8Array(len);
            for (var i=0; i<len; i++) {
                data[i] = passData.charCodeAt(i);
            };

            //var bbClass = undefined;
            var bbClass = window.WebKitBlobBuilder || window.BlobBuilder || window.MozBlobBuilder;
            //if (!bbClass)
            //    throw new Error("WebSocketsWrapper.post: this browser does not support Blobs");               
            if (bbClass)
            {
                var bb = new bbClass();
                bb.append(data.buffer);
                //add messagenr to end
                //bb.append('WSNR');
                //bb.append(parser.encodeInt(12345, 32, false));
                var blob = bb.getBlob("application/octet-stream");
            }
            else
			//use ArrayBuffer instead of Blobs in case (mobile) browser does not support it
			{
               var binarray = data.buffer;
			   var blob = undefined;
			}
        }

        // Create new websocket connection
        if (!this.WS)
        {
            this.WS = new WebSocket(this.urlCall);   //e.g. "ws://localhost:7000/"
            this.WS.WebSocketsWrapper = this;    

            // Called after connection is established
            this.WS.onopen = function() {
                if (isBinary == true) 
                {
                  if (blob)
                    this.send(blob)
                  else 
                    this.send(binarray)
                }
                else
                  //data + messagenr
                  this.send(passData + 'WSNR' + parser.encodeInt(12345, 32, false));
            };

            // Called when a new message is received
            this.WS.onmessage = function(msg) { 
                this.updating = false;
                if (msg.data) 
                {
                  //Text
                  if (typeof msg.data === "string") 
                  {
                    //var parser = new BinaryParser();                  
                    //message nr is last 4 bytes
                    var sWSNR  = msg.data.substr(- 4 - 4, 4);
                    if (!sWSNR === 'WSNR')
                        throw new Error("Message read error: no WSNR at end of data!");
                    var iMsgNr = parser.decodeInt(msg.data.substr(-4), 32, true/*signed)*/);
                    //strip last 4 bytes and 4 chars
                    var adata = msg.data.substring(0, msg.data.length - 4 - 4);
                    onSuccessFunction(adata);
                  }
                  //Blob
                  else 
                  {  
                    var reader = new FileReader();
                    reader.WS = this;
                    
                    reader.onloadend = function() {
                        var parser = new BinaryParser();                  
                        //message nr is last 4 bytes
                           var sWSNR  = reader.result.substr(- 4 - 4, 4);
                        if (!sWSNR === 'WSNR')
                          throw new Error("Message read error: no WSNR at end of data!");
                        var msgNr  = parser.decodeInt(reader.result.substr(-4), 32, true/*signed)*/);
                        
                        //event? (negative msg number)
                        if (msgNr < 0) 
                        {
                            //note: events are always binary?
                            var binmsg = new RemObjects.SDK.BinMessage();
                            binmsg.initialize("", "");
                            binmsg.setResponseStream(reader.result);
                            var sinkName = binmsg.read("", "AnsiString");
                            if (RemObjects.SDK.RTTI[sinkName] && 
                                RemObjects.SDK.RTTI[sinkName].prototype instanceof RemObjects.SDK.ROComplexType) 
                            {
                                var sink = new RemObjects.SDK.RTTI[sinkName]();
                                var eventName = binmsg.read("", "AnsiString");
                                sink.readEvent(binmsg, eventName);
                                //get attached event receiver (other way around, normally reciever use polling :( )
                                var that = this.WS.WebSocketsWrapper.WebSocketClientChannel.FReceiver;                         
                                if (that.fHandlers[eventName]) {
                                    that.fHandlers[eventName](RemObjects.SDK.ROStructType.prototype.toObject.call(sink[eventName]));
                                };
                            } else {
                                throw new Error("EventReceiver.intPollServer: unknown event sink: " + eventName);
                            }
                        }
                        else
                        {
                            //strip last 4 bytes and 4 chars
                            var adata = reader.result.substring(0, reader.result.length - 4 - 4);
                            onSuccessFunction(adata);
                        }                       
                    };
                    //convert blob
                    reader.readAsBinaryString(msg.data);  
                  }  
                }
            };

            //error callback (only the first one?)
            this.WS.onerror = onErrorFunction;
            
            // Called when connection is closed
            this.WS.onclose = function() {
                this.updating = false;        
            }
        }
        //already made, direct send
        else
        {
            //if (this.WS.readyState == 0) { //CONNECTING
                // Called after connection is established
            //    this.WS.onopen += function() {    does not work?
            //        this.send(passData); 
            //    };
            //}
            //else
            if (isBinary == true) 
            {
              if (blob)
                this.send(blob)
              else 
                this.send(binarray)
            }
            else
              this.WS.send(passData + 'WSNR' + parser.encodeInt(12345, 32, false));
        }
    } else {
        alert('Browser doesn\'t support websockets!');
    }
        
    this.WS.updating = new Date();
};   
   
RemObjects.SDK.WebSocketClientChannel = function WebSocketClientChannel(aUrl) {
        RemObjects.SDK.ClientChannel.call(this, aUrl);
    }, 
    
RemObjects.SDK.WebSocketClientChannel.prototype = new RemObjects.SDK.ClientChannel("");
RemObjects.SDK.WebSocketClientChannel.prototype.constructor = RemObjects.SDK.WebSocketClientChannel;
RemObjects.SDK.WebSocketClientChannel.prototype.post = function post(aMessage, isBinary, onSuccess, onError) 
{
    this.ajaxObject = this.ajaxObject || null;
    if (!this.ajaxObject)
      this.ajaxObject = new WebSocketsWrapper(this.url, this);
    this.ajaxObject.post(aMessage, isBinary, onSuccess, onError);
};

RemObjects.SDK.WebSocketClientChannel.prototype.RegisterEventReceiver = function RegisterEventReceiver(aReceiver) 
{
    this.FReceiver = aReceiver;
}

//load data on server side (Node.js)
RemObjects.SDK.JSONMessage.prototype.setRequestStream = function setRequestStream(aRequest) {
    try {
        this.fRequestObject = RemObjects.UTIL.parseJSON(aRequest);
        
        //RO for JS is only meant for the client side (yet :)), so we must copy the request
        //into response, so the .read can read it from there
        this.fResponseObject.result = this.fRequestObject.params; 
    } catch (e) {
        throw new Error("JSONMessage.setRequestStream:\n JSON parsing error: " + e.message + "\nServer response:\n" + aResponse);
    };
};
   