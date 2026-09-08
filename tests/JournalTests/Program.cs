using System.Text.Json;
static void Assert(bool ok,string message){if(!ok)throw new Exception(message);}
Assert(!JsonSerializer.IsReflectionEnabledByDefault,"Test must disable reflection defaults");
foreach(bool created in new[]{false,true}){
    var value=new Journal("中文 空格 & \\" + "\"📦",created,"S-1-5-21-test");
    Assert(JournalJson.Deserialize(JournalJson.Serialize(value))==value,"round-trip failed");
}
const string legacy="{\"Nonce\":\"abc\",\"CertificateCreated\":true,\"UserSid\":\"S-1-5-21-test\"}";
var old=JournalJson.Deserialize(legacy);
Assert(old==new Journal("abc",true,"S-1-5-21-test"),"legacy receipt failed");
Assert(JournalJson.Serialize(old)==legacy,"wire format changed");
foreach(var invalid in new[]{"null","{broken","{\"CertificateCreated\":\"yes\"}"}){
    bool rejected=false;
    try{JournalJson.Deserialize(invalid);}catch(Exception e) when(e is JsonException or InvalidDataException){rejected=true;}
    Assert(rejected,"invalid receipt accepted");
}
Console.WriteLine("PASS reflection disabled: Unicode/boolean round-trips, legacy wire format, null/malformed/type errors");
