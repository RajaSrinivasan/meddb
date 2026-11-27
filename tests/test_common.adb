with Ada.Command_Line;
with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with Meddb.Export;
with Meddb.Hea;
with Meddb.Types;

procedure Test_Common is

   use Ada.Strings.Unbounded;
   use Ada.Text_IO;

   Failures : Natural := 0;

   procedure Check (Condition : Boolean; Message : String) is
   begin
      if Condition then
         Put_Line ("ok: " & Message);
      else
         Put_Line ("FAIL: " & Message);
         Failures := Failures + 1;
      end if;
   end Check;

   function Contains (Path, Needle : String) return Boolean is
      File : File_Type;
      Hit : Boolean := False;
   begin
      Open (File, In_File, Path);
      while not End_Of_File (File) loop
         declare
            Line : constant String := Get_Line (File);
         begin
            if Ada.Strings.Fixed.Index (Line, Needle) > 0 then
               Hit := True;
               exit;
            end if;
         end;
      end loop;
      Close (File);
      return Hit;
   end Contains;

   procedure Test_Export is
      Rec : Meddb.Types.Recording;
      Ch1, Ch2 : Meddb.Types.Channel;
      A : Meddb.Types.Sample_Vectors.Vector;
      B : Meddb.Types.Sample_Vectors.Vector;
      Ann : Meddb.Types.Annotation;
      Dir : constant String := "obj/test-export";
   begin
      Rec.Name := To_Unbounded_String ("synthetic");
      Rec.Format_Name := To_Unbounded_String ("synthetic");
      Rec.Source := To_Unbounded_String ("memory");
      Rec.Start_Time := To_Unbounded_String ("00:00:00");
      Rec.Duration := 1.0;
      Rec.Window_Start := 0.0;
      Rec.Window_Duration := 1.0;
      Rec.Comments.Append (To_Unbounded_String ("unit test"));
      Ch1.Label := To_Unbounded_String ("MLII");
      Ch1.Units := To_Unbounded_String ("mV");
      Ch1.Sampling_Rate := 4.0;
      Ch1.Samples_In_File := 4;
      Ch1.Loaded := True;
      Ch2.Label := To_Unbounded_String ("V5");
      Ch2.Units := To_Unbounded_String ("mV");
      Ch2.Sampling_Rate := 4.0;
      Ch2.Samples_In_File := 4;
      Ch2.Loaded := True;
      Meddb.Types.Add_Channel (Rec, Ch1);
      Meddb.Types.Add_Channel (Rec, Ch2);
      A.Append (0.1);
      A.Append (0.2);
      A.Append (-0.3);
      A.Append (0.4);
      B.Append (-0.5);
      B.Append (0.6);
      B.Append (0.7);
      B.Append (-0.8);
      Meddb.Types.Set_Samples (Rec, 1, A);
      Meddb.Types.Set_Samples (Rec, 2, B);
      Ann.Onset := 0.25;
      Ann.Duration := 0.0;
      Ann.Label := To_Unbounded_String ("N");
      Ann.Description := To_Unbounded_String ("Normal beat");
      Rec.Annotations.Append (Ann);
      Rec.Annotations_In_File := 1;
      Ada.Directories.Create_Path (Dir);
      Meddb.Export.Write (Rec, Dir & "/synthetic");
      Check (Ada.Directories.Exists (Dir & "/synthetic.csv"), "csv exists");
      Check (Ada.Directories.Exists (Dir & "/synthetic.json"), "json exists");
      Check (Contains (Dir & "/synthetic.csv", "time_s,MLII,V5"), "csv header");
      Check (Contains (Dir & "/synthetic.csv", "0.1"), "csv sample");
      Check (Contains (Dir & "/synthetic.json", """label"": ""N"""), "json annotation");
      Check (Contains (Dir & "/synthetic.json", "MLII"), "json channel");
      Check (Meddb.Types.Loaded_Count (Rec) = 2, "two loaded channels");
   end Test_Export;

   procedure Test_Hea is
      Dir : constant String := "obj/test-hea";
      Rec : Meddb.Types.Recording;
      File : File_Type;
   begin
      Ada.Directories.Create_Path (Dir);
      Create (File, Out_File, Dir & "/A0001.hea");
      Put_Line (File, "A0001 12 500 7500");
      Put_Line (File, "A0001.mat 16x1+24 1000.0(0)/mV 16 0 28 -1716 0 I");
      Put_Line (File, "A0001.mat 16x1+24 1000.0(0)/mV 16 0 7 2029 0 II");
      Put_Line (File, "# Dx: 59118001");
      Close (File);
      Meddb.Hea.Load (Dir & "/A0001.hea", Rec);
      Check (Natural (Rec.Channels.Length) = 2, "hea channel count");
      Check (Rec.Channels (1).Label = "I", "hea lead I");
      Check (Rec.Channels (2).Label = "II", "hea lead II");
      Check (Rec.Channels (1).Sampling_Rate = 500.0, "hea sampling rate");
      Check (Rec.Channels (1).Gain = 1000.0, "hea gain");
      Check (Rec.Channels (1).Units = "mV", "hea units");
      Check (Rec.Channels (1).Samples_In_File = 7500, "hea sample count");
      Check (Rec.Duration = 15.0, "hea duration");
      Check (not Rec.Comments.Is_Empty, "hea comment");
   end Test_Hea;

   procedure Test_Window is
      Load : Boolean;
      Span : Long_Float;
      Req : Meddb.Types.Read_Request;
   begin
      Meddb.Types.Decide_Load (1805.0, 360.0, Req, Load, Span);
      Check (Load and then Span = 30.0, "default window is 30 s");
      Req.Duration := 5.0;
      Meddb.Types.Decide_Load (1805.0, 44100.0, Req, Load, Span);
      Check (Load and then Span = 5.0, "explicit duration loads fast signals");
      Req.Duration := -1.0;
      Meddb.Types.Decide_Load (8.0, 44100.0, Req, Load, Span);
      Check (not Load, "fast signals stay unloaded by default");
   end Test_Window;

begin
   Test_Export;
   Test_Hea;
   Test_Window;
   if Failures > 0 then
      Put_Line ("failures:" & Natural'Image (Failures));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   else
      Put_Line ("all common tests passed");
   end if;
end Test_Common;
