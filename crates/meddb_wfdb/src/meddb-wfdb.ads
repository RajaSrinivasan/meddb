with Meddb.Types;

package Meddb.Wfdb is

   procedure Read
     (Path      : String;
      Req       : Types.Read_Request;
      Annotator : String;
      Rec       : out Types.Recording);

end Meddb.Wfdb;
