with Meddb.Types;

package Meddb.Edf is

   procedure Read
     (Path      : String;
      Req       : Types.Read_Request;
      Hypnogram : String;
      Rec       : out Types.Recording);

end Meddb.Edf;
