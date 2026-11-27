with Meddb.Types;

package Meddb.Hea is

   procedure Load (Path : String; Rec : in out Types.Recording);

   function Sibling_Hea (Signal_Path : String) return String;

end Meddb.Hea;
