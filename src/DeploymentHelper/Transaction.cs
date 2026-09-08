// Small shared rollback mechanism, also compiled into the no-install unit tests.
internal sealed class Transaction {
    readonly Stack<(string Name,Func<Task> Undo)> undo=new();
    public async Task Step(string name,Func<Task> apply,Func<Task> rollback) {
        undo.Push((name,rollback)); // include a step that fails after partially mutating
        await apply();
    }
    public void Commit()=>undo.Clear();
    public async Task Rollback() {
        while(undo.TryPeek(out var item)) {
            try{await item.Undo();undo.Pop();}
            catch(Exception ex){throw new Exception("Rollback incomplete at "+item.Name+"; keep dependent resources for safe recovery.",ex);}
        }
    }
}
