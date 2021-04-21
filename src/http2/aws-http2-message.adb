------------------------------------------------------------------------------
--                              Ada Web Server                              --
--                                                                          --
--                      Copyright (C) 2021, AdaCore                         --
--                                                                          --
--  This library is free software;  you can redistribute it and/or modify   --
--  it under terms of the  GNU General Public License  as published by the  --
--  Free Software  Foundation;  either version 3,  or (at your  option) any --
--  later version. This library is distributed in the hope that it will be  --
--  useful, but WITHOUT ANY WARRANTY;  without even the implied warranty of --
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.                    --
--                                                                          --
--  As a special exception under Section 7 of GPL version 3, you are        --
--  granted additional permissions described in the GCC Runtime Library     --
--  Exception, version 3.1, as published by the Free Software Foundation.   --
--                                                                          --
--  You should have received a copy of the GNU General Public License and   --
--  a copy of the GCC Runtime Library Exception along with this program;    --
--  see the files COPYING3 and COPYING.RUNTIME respectively.  If not, see   --
--  <http://www.gnu.org/licenses/>.                                         --
--                                                                          --
--  As a special exception, if other files instantiate generics from this   --
--  unit, or you link this unit with other files to produce an executable,  --
--  this  unit  does not  by itself cause  the resulting executable to be   --
--  covered by the GNU General Public License. This exception does not      --
--  however invalidate any other reasons why the executable file  might be  --
--  covered by the  GNU Public License.                                     --
------------------------------------------------------------------------------

with Ada.Calendar;
with Ada.Streams;

with AWS.HTTP2.Connection;
with AWS.HTTP2.Frame.Continuation;
with AWS.HTTP2.Frame.Data;
with AWS.HTTP2.Frame.Headers;
with AWS.Messages;
with AWS.Resources;
with AWS.Server.HTTP_Utils;
with AWS.Status;
with AWS.Translator;
with AWS.Utils;

package body AWS.HTTP2.Message is

   use Ada.Streams;

   ------------
   -- Create --
   ------------

   function Create
     (Headers : AWS.Headers.List;
      Payload : Unbounded_String)
      return Object is
   begin
      return O : Object (Response.Message) do
         O.Headers := Headers;
         O.Payload := Payload;
      end return;
   end Create;

   function Create
     (Headers  : AWS.Headers.List;
      Filename : String)
      return Object is
   begin
      return O : Object (Response.File) do
         O.Headers  := Headers;
         O.Filename := To_Unbounded_String (Filename);
      end return;
   end Create;

   ---------------
   -- To_Frames --
   ---------------

   function To_Frames
     (Self      : Object;
      Ctx       : in out Server.Context.Object;
      Stream_Id : HTTP2.Stream_Id)
      return AWS.HTTP2.Frame.List.Object
   is
      use type Status.Request_Method;

      List : Frame.List.Object;
      --  The list of created frames

      Method : constant Status.Request_Method := Status.Method (Ctx.Status);

      procedure Handle_Headers (Headers : AWS.Headers.List);
      --  Create the header frames

      procedure From_Content (Data : Unbounded_String);
      --  Creates the data frame from a content

      procedure From_File (File : in out Resources.File_Type);
      --  Creates the data frame from filename content

      procedure Create_Data_Frame
        (Content : Utils.Stream_Element_Array_Access);
      --  Create a new data frame from Content

      procedure Create_Data_Frame (Content : Stream_Element_Array);
      --  Create a new data frame from Content

      -----------------------
      -- Create_Data_Frame --
      -----------------------

      procedure Create_Data_Frame (Content : Stream_Element_Array) is
      begin
         Create_Data_Frame (new Stream_Element_Array'(Content));
      end Create_Data_Frame;

      procedure Create_Data_Frame
        (Content : Utils.Stream_Element_Array_Access) is
      begin
         List.Append (Frame.Data.Create (Stream_Id, Content));
      end Create_Data_Frame;

      ------------------
      -- From_Content --
      ------------------

      procedure From_Content (Data : Unbounded_String) is

         Size       : constant Positive := Length (Data);
         Max_Size   : constant Stream_Element_Count :=
                        Stream_Element_Count
                          (Connection.Max_Frame_Size (Ctx.Settings.all));
         Chunk_Size : constant := 4_096;

         package Buffer is new Utils.Buffered_Data
           (Max_Size, Create_Data_Frame);

         First : Positive := 1;
         Last  : Positive;
      begin
         while First < Size loop
            Last := Positive'Min (First + Chunk_Size - 1, Size);

            Buffer.Add
              (Translator.To_Stream_Element_Array
                 (Slice (Data, First, Last)));

            First := Last + 1;
         end loop;

         Buffer.Flush;
      end From_Content;

      ---------------
      -- From_File --
      ---------------

      procedure From_File (File : in out Resources.File_Type) is
         Length : Resources.Content_Length_Type := 0;

         procedure Send_File is
           new Server.HTTP_Utils.Send_File_G (Create_Data_Frame);

      begin
         Send_File (Ctx.HTTP.all, Ctx.Line, File, Length);
      end From_File;

      --------------------
      -- Handle_Headers --
      --------------------

      procedure Handle_Headers (Headers : AWS.Headers.List) is
         Max_Size : constant Positive :=
                      Connection.Max_Header_List_Size (Ctx.Settings.all);
         L        : AWS.Headers.List;
         Size     : Natural := 0;
         Is_First : Boolean := True;
      begin
         for K in 1 .. Headers.Count loop
            declare
               Element : constant AWS.Headers.Element := Headers.Get (K);
               E_Size  : constant Positive :=
                           32 + Length (Element.Name) + Length (Element.Value);
            begin
               Size := Size + E_Size;

               --  Max header size reached, let's send this as a first frame
               --  and will continue in a continuation frame if necessary.

               if Size > Max_Size then
                  if Is_First then
                     List.Append
                       (Frame.Headers.Create
                          (Ctx.Table, Stream_Id, L,
                           End_Headers => K = Headers.Count));
                     Is_First := False;
                  else
                     List.Append
                       (Frame.Continuation.Create
                          (Ctx.Table, Stream_Id, L,
                           End_Headers => K = Headers.Count));
                  end if;

                  L.Reset;
                  Size := E_Size;
               end if;

               L.Add (Element.Name, Element.Value);
            end;
         end loop;

         if not L.Is_Empty then
            List.Append
              (Frame.Headers.Create
                 (Ctx.Table, Stream_Id, L, End_Headers => True));
         end if;
      end Handle_Headers;

      Status_Code : Messages.Status_Code :=
                      Response.Status_Code (Ctx.Response);
      With_Body   : constant Boolean :=
                      Messages.With_Body (Status_Code)
                        and then Method /= Status.HEAD
                        and then Self.Mode /= Response.Header;
      Headers     : AWS.Headers.List;

   begin
      case Self.Mode is
         when Response.Message | Response.Header =>
            --  Set status code

            Headers.Add
              (Messages.Status_Token,
               Messages.Image (Status_Code));

            Headers := Headers.Union (Self.Headers, True);

            Handle_Headers (Headers);

            if With_Body then
               From_Content (Self.Payload);
            end if;

         when Response.File | Response.File_Once | Response.Stream =>
            declare
               use all type Server.HTTP_Utils.Resource_Status;

               File_Time : Ada.Calendar.Time;
               F_Status  : constant Server.HTTP_Utils.Resource_Status :=
                             Server.HTTP_Utils.Get_Resource_Status
                               (Ctx.Status,
                                To_String (Self.Filename),
                                File_Time);
               File      : Resources.File_Type;
            begin
               --  Status code header

               case F_Status is
                  when Changed    =>
                     if AWS.Headers.Get_Values
                       (Status.Header (Ctx.Status), Messages.Range_Token) /= ""
                       and then With_Body
                     then
                        Status_Code := Messages.S200;
                     end if;

                  when Up_To_Date =>
                     Status_Code := Messages.S304;

                  when Not_Found  =>
                     Status_Code := Messages.S404;
               end case;

               Response.Create_Resource
                 (Ctx.Response,
                  File,
                  AWS.Status.Is_Supported (Ctx.Status, Messages.GZip));

               --  Add some standard and file oriented headers

               Headers.Add
                 (Messages.Status_Token,
                  Messages.Image (Status_Code));

               if Resources.Size (File) /= Resources.Undefined_Length then
                  Headers.Add
                    (Messages.Content_Length_Token,
                     Stream_Element_Offset'Image (Resources.Size (File)));
               end if;

               if not Response.Has_Header
                 (Ctx.Response,
                  Messages.Last_Modified_Token)
               then
                  Headers.Add
                    (Messages.Last_Modified_Token,
                     Messages.To_HTTP_Date (File_Time));
               end if;

               Headers := Headers.Union (Self.Headers, True);

               Handle_Headers (Headers);

               --  If file is not found the header only is sufficient,
               --  otherwise let's send the file.

               --  ??? File ranges not supported yet

               if With_Body and then F_Status = Changed then
                  From_File (File);
               end if;
            end;

         when Response.WebSocket =>
            raise Constraint_Error with "websocket is HTTP/1.1 only";

         when Response.Socket_Taken =>
            raise Constraint_Error with "not yet supported";

         when Response.No_Data =>
            raise Constraint_Error with "no_data should never happen";
      end case;

      return List;
   end To_Frames;

end AWS.HTTP2.Message;
