with Ada.Command_Line;
with Ada.Exceptions;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with Meddb.CLI;
with Meddb.Types;
with Meddb.Wfdb;

procedure Meddb_Wfdb is
   use Ada.Strings.Unbounded;
   Opts : Meddb.CLI.Options;
   Input : Ada.Strings.Unbounded.Unbounded_String;
   Rec : Meddb.Types.Recording;
begin
   Meddb.CLI.Parse ("meddb-wfdb", Opts, Input);
   if Opts.Help or else Input = "" then
      Meddb.CLI.Print_Usage ("meddb-wfdb");
      if not Opts.Help then
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      end if;
      return;
   end if;
   Meddb.Wfdb.Read
     (Ada.Strings.Unbounded.To_String (Input),
      Meddb.CLI.Request (Opts),
      Ada.Strings.Unbounded.To_String (Opts.Annotator),
      Rec);
   Meddb.CLI.Report (Rec, Opts);
exception
   when E : Meddb.Error =>
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error, "error: " & Ada.Exceptions.Exception_Message (E));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
end Meddb_Wfdb;
