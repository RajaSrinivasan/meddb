with Ada.Command_Line;
with Ada.Exceptions;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with Meddb.CLI;
with Meddb.Hdf5;
with Meddb.Types;

procedure Meddb_Hdf5 is
   use Ada.Strings.Unbounded;
   Opts : Meddb.CLI.Options;
   Input : Ada.Strings.Unbounded.Unbounded_String;
   Rec : Meddb.Types.Recording;
begin
   Meddb.CLI.Parse ("meddb-hdf5", Opts, Input);
   if Opts.Help or else Input = "" then
      Meddb.CLI.Print_Usage ("meddb-hdf5");
      if not Opts.Help then
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      end if;
      return;
   end if;
   Meddb.Hdf5.Read
     (Ada.Strings.Unbounded.To_String (Input),
      Meddb.CLI.Request (Opts),
      Rec);
   if Opts.List_Only then
      Opts.Export_Prefix := Ada.Strings.Unbounded.Null_Unbounded_String;
   end if;
   Meddb.CLI.Report (Rec, Opts);
exception
   when E : Meddb.Error =>
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error, "error: " & Ada.Exceptions.Exception_Message (E));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
end Meddb_Hdf5;
