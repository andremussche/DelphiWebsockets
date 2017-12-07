unit IdWebSocketTypes;

interface
type
  TWSDataType      = (wdtText, wdtBinary);
  TWSDataCode      = (wdcNone, wdcContinuation, wdcText, wdcBinary, wdcClose, wdcPing, wdcPong);
  TWSExtensionBit  = (webBit1, webBit2, webBit3);
  TWSExtensionBits = set of TWSExtensionBit;
  TIdWebSocketRequestType = (wsrtGet, wsrtPost);

implementation

end.
