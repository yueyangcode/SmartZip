static void Assert(bool ok,string message){if(!ok)throw new Exception(message);}
foreach(var c in new[]{
    (true,true,false,(int?)1,3,true), // filtered admin
    (true,true,false,(int?)1,1,true), // standard user
    (true,true,true,(int?)0,1,true), // UAC-off desktop admin
    (true,true,true,(int?)1,2,false), // explicit elevation
    (false,true,true,(int?)0,1,false), // another account
    (false,true,false,(int?)1,1,false),
    (true,false,true,(int?)0,1,false), // another session
    (true,true,true,(int?)null,1,false), // unknown policy
    (true,true,true,(int?)0,2,false), // pending reboot / split token
    (true,true,true,(int?)1,1,false),
    (true,true,false,(int?)1,0,false)
})Assert(UserContext.Allowed(c.Item1,c.Item2,c.Item3,c.Item4,c.Item5)==c.Item6,"user-context policy regression");
Console.WriteLine("PASS 11 identity/UAC/token policy cases");
if(OperatingSystem.IsWindows())UserContext.Require(Console.WriteLine); // read-only actual desktop/token check
foreach(var preexistingCert in new[]{false,true})foreach(var failure in new[]{"files","certificate","package","package-verify","com-verify"}){
    HashSet<string> state=new();if(preexistingCert)state.Add("certificate");List<string> order=new();var tx=new Transaction();
    try{
        foreach(var step in new[]{"files","certificate","package"}){
            bool existed=state.Contains(step);
            await tx.Step(step,()=>{state.Add(step);if(step==failure)throw new IOException("injected partial failure");return Task.CompletedTask;},()=>{order.Add(step);if(!existed)state.Remove(step);return Task.CompletedTask;});
        }
        throw new IOException("injected "+failure);
    }catch(IOException){await tx.Rollback();}
    Assert(state.SetEquals(preexistingCert?new[]{"certificate"}:Array.Empty<string>()),"baseline not restored: "+failure);
    Assert(order.Last()=="files","files must be last");
    if(order.Contains("package"))Assert(order[0]=="package","package must be first");
    Console.WriteLine($"PASS partial failure={failure}, preexisting certificate={preexistingCert}: baseline restored");
}
{
    var tx=new Transaction();bool filePresent=true;
    await tx.Step("files",()=>Task.CompletedTask,()=>{filePresent=false;return Task.CompletedTask;});
    await tx.Step("package",()=>Task.CompletedTask,()=>throw new IOException("removal blocked"));
    bool threw=false;try{await tx.Rollback();}catch(Exception){threw=true;}
    Assert(threw&&filePresent,"failed package rollback must not delete backing files or claim success");
    Console.WriteLine("PASS rollback failure is surfaced, backing files preserved");
}
{
    var tx=new Transaction();bool undone=false;
    await tx.Step("committed",()=>Task.CompletedTask,()=>{undone=true;return Task.CompletedTask;});tx.Commit();await tx.Rollback();Assert(!undone,"committed transaction unexpectedly undone");
    Console.WriteLine("PASS successful commit clears rollback actions");
}
