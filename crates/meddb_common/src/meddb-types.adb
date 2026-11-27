with Ada.Strings.Fixed;
with Ada.Text_IO;

package body Meddb.Types is

   function Trim (S : String) return String is
   begin
      return Ada.Strings.Fixed.Trim (S, Ada.Strings.Both);
   end Trim;

   function Format_Number (X : Long_Float; Aft : Positive := 6) return String is
      package FIO is new Ada.Text_IO.Float_IO (Long_Float);
      Buf : String (1 .. 64);
   begin
      if X = Long_Float'Floor (X)
        and then abs X < 1.0e15
      then
         return Trim (Long_Long_Integer'Image (Long_Long_Integer (X)));
      end if;
      FIO.Put (Buf, X, Aft => Aft, Exp => 0);
      return Trim (Buf);
   end Format_Number;

   procedure Add_Channel (Rec : in out Recording; Item : Channel) is
   begin
      Rec.Channels.Append (Item);
      Rec.Samples.Append (Sample_Vectors.Empty_Vector);
   end Add_Channel;

   procedure Set_Samples
     (Rec   : in out Recording;
      Index : Positive;
      Data  : Sample_Vectors.Vector)
   is
      Item : Channel := Rec.Channels (Index);
   begin
      Rec.Samples.Replace_Element (Index, Data);
      Item.Loaded := not Data.Is_Empty;
      Rec.Channels.Replace_Element (Index, Item);
   end Set_Samples;

   function Loaded_Count (Rec : Recording) return Natural is
      N : Natural := 0;
   begin
      for Ch of Rec.Channels loop
         if Ch.Loaded then
            N := N + 1;
         end if;
      end loop;
      return N;
   end Loaded_Count;

   procedure Decide_Load
     (File_Duration : Long_Float;
      Rate          : Long_Float;
      Req           : Read_Request;
      Do_Load       : out Boolean;
      Span          : out Long_Float)
   is
      Remaining : Long_Float;
      Wanted    : Long_Float;
      Cap       : Long_Float;
   begin
      Do_Load := False;
      Span := 0.0;
      if File_Duration <= 0.0 then
         return;
      end if;
      Remaining := File_Duration - Req.Start;
      if Remaining <= 0.0 then
         return;
      end if;
      if Req.Duration > 0.0 then
         Wanted := Long_Float'Min (Req.Duration, Remaining);
      elsif Req.Full then
         Wanted := Remaining;
      else
         if Rate > Fast_Rate_Hz then
            return;
         end if;
         Wanted := Long_Float'Min (Default_Window_Seconds, Remaining);
      end if;
      if Rate > 0.0 then
         Cap := Long_Float (Max_Loaded_Samples) / Rate;
         if Wanted > Cap then
            Wanted := Cap;
         end if;
      end if;
      if Wanted <= 0.0 then
         return;
      end if;
      Do_Load := True;
      Span := Wanted;
   end Decide_Load;

   function Start_Index
     (Rate       : Long_Float;
      Start_Time : Long_Float) return Long_Long_Integer
   is
   begin
      if Rate <= 0.0 or else Start_Time <= 0.0 then
         return 0;
      end if;
      return Long_Long_Integer (Long_Float'Floor (Start_Time * Rate));
   end Start_Index;

   function Sample_Count
     (Rate       : Long_Float;
      Span       : Long_Float;
      Available  : Long_Long_Integer;
      Start_Time : Long_Float) return Long_Long_Integer
   is
      Origin : constant Long_Long_Integer := Start_Index (Rate, Start_Time);
      Count  : Long_Long_Integer;
      Left   : Long_Long_Integer;
   begin
      if Rate <= 0.0 or else Span <= 0.0 or else Available <= 0 then
         return 0;
      end if;
      if Origin >= Available then
         return 0;
      end if;
      Count := Long_Long_Integer (Long_Float'Rounding (Span * Rate));
      if Count < 1 then
         Count := 1;
      end if;
      Left := Available - Origin;
      if Count > Left then
         Count := Left;
      end if;
      return Count;
   end Sample_Count;

end Meddb.Types;
