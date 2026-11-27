with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;

package Meddb.Types is

   use Ada.Strings.Unbounded;

   Default_Window_Seconds : constant Long_Float := 30.0;
   Fast_Rate_Hz           : constant Long_Float := 2_000.0;
   Max_Loaded_Samples     : constant          := 2_000_000;

   type Read_Request is record
      Start    : Long_Float := 0.0;
      Duration : Long_Float := -1.0;
      Full     : Boolean    := False;
   end record;

   type Channel is record
      Label           : Unbounded_String;
      Units           : Unbounded_String;
      Sampling_Rate   : Long_Float          := 0.0;
      Physical_Min    : Long_Float          := 0.0;
      Physical_Max    : Long_Float          := 0.0;
      Digital_Min     : Integer             := 0;
      Digital_Max     : Integer             := 0;
      Gain            : Long_Float          := 0.0;
      Baseline        : Integer             := 0;
      Samples_In_File : Long_Long_Integer   := 0;
      Loaded          : Boolean             := False;
      Note            : Unbounded_String;
   end record;

   package Sample_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Long_Float);

   package Channel_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Channel);

   use type Sample_Vectors.Vector;

   package Sample_List is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Sample_Vectors.Vector);

   type Annotation is record
      Onset       : Long_Float := 0.0;
      Duration    : Long_Float := 0.0;
      Label       : Unbounded_String;
      Channel     : Unbounded_String;
      Description : Unbounded_String;
   end record;

   package Annotation_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Annotation);

   package String_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Unbounded_String);

   type Dimension_Array is array (1 .. 4) of Long_Long_Integer;

   type Structure_Node is record
      Path       : Unbounded_String;
      Dtype      : Unbounded_String;
      Rank       : Natural            := 0;
      Dims       : Dimension_Array    := (others => 0);
      N_Elements : Long_Long_Integer  := 0;
   end record;

   package Node_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Structure_Node);

   type Recording is record
      Name                 : Unbounded_String;
      Format_Name          : Unbounded_String;
      Source               : Unbounded_String;
      Start_Time           : Unbounded_String;
      Duration             : Long_Float := 0.0;
      Window_Start         : Long_Float := 0.0;
      Window_Duration      : Long_Float := 0.0;
      Comments             : String_Vectors.Vector;
      Channels             : Channel_Vectors.Vector;
      Samples              : Sample_List.Vector;
      Annotations          : Annotation_Vectors.Vector;
      Annotations_In_File  : Natural := 0;
      Structure            : Node_Vectors.Vector;
   end record;

   procedure Add_Channel (Rec : in out Recording; Item : Channel);

   procedure Set_Samples
     (Rec   : in out Recording;
      Index : Positive;
      Data  : Sample_Vectors.Vector);

   function Loaded_Count (Rec : Recording) return Natural;

   procedure Decide_Load
     (File_Duration : Long_Float;
      Rate          : Long_Float;
      Req           : Read_Request;
      Do_Load       : out Boolean;
      Span          : out Long_Float);

   function Sample_Count
     (Rate       : Long_Float;
      Span       : Long_Float;
      Available  : Long_Long_Integer;
      Start_Time : Long_Float) return Long_Long_Integer;

   function Start_Index
     (Rate       : Long_Float;
      Start_Time : Long_Float) return Long_Long_Integer;

   function Format_Number (X : Long_Float; Aft : Positive := 6) return String;

   function Trim (S : String) return String;

end Meddb.Types;
