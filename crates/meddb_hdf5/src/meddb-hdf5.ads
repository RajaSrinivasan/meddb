with Meddb.Types;

package Meddb.Hdf5 is

   procedure Read
     (Path : String;
      Req  : Types.Read_Request;
      Rec  : out Types.Recording);

end Meddb.Hdf5;
