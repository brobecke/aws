------------------------------------------------------------------------------
--                              Ada Web Server                              --
--                                                                          --
--                         Copyright (C) 2000-2001                          --
--                                ACT-Europe                                --
--                                                                          --
--  Authors: Dmitriy Anisimkov - Pascal Obry                                --
--                                                                          --
--  This library is free software; you can redistribute it and/or modify    --
--  it under the terms of the GNU General Public License as published by    --
--  the Free Software Foundation; either version 2 of the License, or (at   --
--  your option) any later version.                                         --
--                                                                          --
--  This library is distributed in the hope that it will be useful, but     --
--  WITHOUT ANY WARRANTY; without even the implied warranty of              --
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU       --
--  General Public License for more details.                                --
--                                                                          --
--  You should have received a copy of the GNU General Public License       --
--  along with this library; if not, write to the Free Software Foundation, --
--  Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.          --
--                                                                          --
--  As a special exception, if other files instantiate generics from this   --
--  unit, or you link this unit with other files to produce an executable,  --
--  this  unit  does not  by itself cause  the resulting executable to be   --
--  covered by the GNU General Public License. This exception does not      --
--  however invalidate any other reasons why the executable file  might be  --
--  covered by the  GNU Public License.                                     --
------------------------------------------------------------------------------

--  $Id$

with Ada.Unchecked_Deallocation;

package body AWS.Containers.Tables.Set is

   procedure Reset (Table : in out Index_Table_Type);
   --  Free all elements and destroy his entries.

   procedure Free is new Ada.Unchecked_Deallocation (String, String_Access);

   procedure Free_Elements (Data : in out Data_Table.Instance);
   --  Free all dynamically allocated strings in the data table.

   ---------
   -- Add --
   ---------

   procedure Add
     (Table       : in out Table_Type;
      Name, Value : in     String)
   is

      L_Key   : constant String   := Normalize_Name
        (Name, not Table.Case_Sensitive);

      Found   : Boolean;

      Item    : Element :=
        (Name => new String'(Name),
         Value => new String'(Value));

      procedure Modify
        (Key   : in     String;
         Value : in out Name_Index_Table);

      ------------
      -- Modify --
      ------------

      procedure Modify
        (Key   : in     String;
         Value : in out Name_Index_Table)
      is
         pragma Warnings (Off, Key);
      begin
         Name_Indexes.Append (Value, Data_Table.Last (Table.Data));
      end Modify;

      procedure Update is new Index_Table.Update_Value_Or_Status_G (Modify);

   begin

      Data_Table.Append (Table.Data, Item);

      Update
        (Table => Index_Table.Table_Type (Table.Index.all),
         Key   => L_Key,
         Found => Found);

      if not Found then
         declare
            Value : Name_Index_Table;
         begin
            Name_Indexes.Init (Value);
            Name_Indexes.Append (Value, Data_Table.Last (Table.Data));
            Insert (Table.Index.all, L_Key, Value);
         end;
      end if;

   end Add;

   --------------------
   -- Case_Sensitive --
   --------------------

   procedure Case_Sensitive
     (Table : in out Table_Type;
      Mode  : in     Boolean) is
   begin
      Table.Case_Sensitive := Mode;
   end Case_Sensitive;

   ----------
   -- Free --
   ----------

   procedure Free (Table : in out Table_Type) is

      procedure Free is
         new Ada.Unchecked_Deallocation (Index_Table_Type, Index_Access);

   begin
      if Table.Index /= null then
         Reset (Table.Index.all);
         Free (Table.Index);

         Free_Elements (Table.Data);
         Data_Table.Free (Table.Data);
      end if;
   end Free;

   -------------------
   -- Free_Elements --
   -------------------

   procedure Free_Elements (Data : in out Data_Table.Instance) is
   begin
      for I in Data_Table.First .. Data_Table.Last (Data) loop
         Free (Data.Table (I).Name);
         Free (Data.Table (I).Value);
      end loop;
   end Free_Elements;

   -----------
   -- Reset --
   -----------

   procedure Reset (Table : in out Index_Table_Type)
   is

      procedure Modify
        (Key          : in     String;
         Value        : in out Name_Index_Table;
         Order_Number : in     Positive;
         Continue     : in out Boolean);

      ------------
      -- Modify --
      ------------

      procedure Modify
        (Key          : in     String;
         Value        : in out Name_Index_Table;
         Order_Number : in     Positive;
         Continue     : in out Boolean)
      is
         pragma Warnings (Off, Key);
         pragma Warnings (Off, Order_Number);
         pragma Warnings (Off, Continue);
      begin
         Name_Indexes.Free (Value);
      end Modify;

      procedure Traverse is new
         Index_Table.Disorder_Traverse_And_Update_Value_G (Modify);

   begin
      Traverse (Index_Table.Table_Type (Table));
      Destroy (Table);
   end Reset;

   procedure Reset (Table : in out Table_Type) is
   begin
      if Table.Index = null then
         Table.Index := new Index_Table_Type;
      else
         Reset (Table.Index.all);
         Free_Elements (Table.Data);
      end if;
      Data_Table.Init (Table.Data);
   end Reset;

end AWS.Containers.Tables.Set;
