with Ada.Command_Line;
with Ada.Exceptions;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with Meddb.Aecg;
with Meddb.CLI;
with Meddb.Types;

procedure Meddb_Aecg is
   use Ada.Strings.Unbounded;
   Opts : Meddb.CLI.Options;
   Input : Ada.Strings.Unbounded.Unbounded_String;
   Rec : Meddb.Types.Recording;
begin
   Meddb.CLI.Parse ("meddb-aecg", Opts, Input);
   if Opts.Help or else Input = "" then
      Meddb.CLI.Print_Usage ("meddb-aecg");
      Ada.Text_IO.Put_Line
        ("HL7 aECG reader. Waveforms come from libbiosig; annotation regions are read from the XML.");
      Ada.Text_IO.Put_Line
        ("No public real clinical aECG corpus was available as of 26 Nov 2026.");
      Ada.Text_IO.Put_Line
        ("The downloadable example is the official HL7 2003-12 schema fixture, not a clinical recording.");
      if not Opts.Help then
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      end if;
      return;
   end if;
   Meddb.Aecg.Read
     (Ada.Strings.Unbounded.To_String (Input),
      Meddb.CLI.Request (Opts),
      Rec);
   Meddb.CLI.Report (Rec, Opts);
exception
   when E : Meddb.Error =>
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error, "error: " & Ada.Exceptions.Exception_Message (E));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
end Meddb_Aecg;
