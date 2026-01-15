export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "13.0.5"
  }
  public: {
    Tables: {
      app_versions: {
        Row: {
          apk_url: string
          app_type: string
          created_at: string | null
          id: string
          is_force_update: boolean | null
          release_notes: string | null
          version: string
        }
        Insert: {
          apk_url: string
          app_type: string
          created_at?: string | null
          id?: string
          is_force_update?: boolean | null
          release_notes?: string | null
          version: string
        }
        Update: {
          apk_url?: string
          app_type?: string
          created_at?: string | null
          id?: string
          is_force_update?: boolean | null
          release_notes?: string | null
          version?: string
        }
        Relationships: []
      }
      attendance: {
        Row: {
          check_in: string
          check_out: string | null
          created_at: string | null
          date: string
          id: string
          is_early_leave: boolean | null
          is_overtime: boolean | null
          organization_code: string
          shift_end_time: string | null
          shift_name: string | null
          shift_start_time: string | null
          status: string | null
          worker_id: string
        }
        Insert: {
          check_in?: string
          check_out?: string | null
          created_at?: string | null
          date?: string
          id?: string
          is_early_leave?: boolean | null
          is_overtime?: boolean | null
          organization_code: string
          shift_end_time?: string | null
          shift_name?: string | null
          shift_start_time?: string | null
          status?: string | null
          worker_id: string
        }
        Update: {
          check_in?: string
          check_out?: string | null
          created_at?: string | null
          date?: string
          id?: string
          is_early_leave?: boolean | null
          is_overtime?: boolean | null
          organization_code?: string
          shift_end_time?: string | null
          shift_name?: string | null
          shift_start_time?: string | null
          status?: string | null
          worker_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "attendance_worker_id_fkey"
            columns: ["worker_id"]
            isOneToOne: false
            referencedRelation: "workers"
            referencedColumns: ["worker_id"]
          },
        ]
      }
      daily_geofence_summaries: {
        Row: {
          created_at: string | null
          date: string
          entry_count: number | null
          exit_count: number | null
          first_entry_time: string | null
          id: string
          last_event_time: string | null
          organization_code: string
          worker_id: string
        }
        Insert: {
          created_at?: string | null
          date?: string
          entry_count?: number | null
          exit_count?: number | null
          first_entry_time?: string | null
          id?: string
          last_event_time?: string | null
          organization_code: string
          worker_id: string
        }
        Update: {
          created_at?: string | null
          date?: string
          entry_count?: number | null
          exit_count?: number | null
          first_entry_time?: string | null
          id?: string
          last_event_time?: string | null
          organization_code?: string
          worker_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "daily_geofence_summaries_worker_id_fkey"
            columns: ["worker_id"]
            isOneToOne: false
            referencedRelation: "workers"
            referencedColumns: ["worker_id"]
          },
        ]
      }
      gate_events: {
        Row: {
          created_at: string
          event_type: string
          id: string
          latitude: number
          longitude: number
          organization_code: string
          timestamp: string
          worker_id: string
        }
        Insert: {
          created_at?: string
          event_type: string
          id?: string
          latitude: number
          longitude: number
          organization_code: string
          timestamp?: string
          worker_id: string
        }
        Update: {
          created_at?: string
          event_type?: string
          id?: string
          latitude?: number
          longitude?: number
          organization_code?: string
          timestamp?: string
          worker_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "gate_events_worker_id_fkey"
            columns: ["worker_id"]
            isOneToOne: false
            referencedRelation: "workers"
            referencedColumns: ["worker_id"]
          },
        ]
      }
      items: {
        Row: {
          created_at: string
          id: string
          item_id: string
          name: string
          operation_details: Json | null
          operations: string[]
          organization_code: string | null
        }
        Insert: {
          created_at?: string
          id?: string
          item_id: string
          name: string
          operation_details?: Json | null
          operations: string[]
          organization_code?: string | null
        }
        Update: {
          created_at?: string
          id?: string
          item_id?: string
          name?: string
          operation_details?: Json | null
          operations?: string[]
          organization_code?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "items_org_code_fk"
            columns: ["organization_code"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["organization_code"]
          },
          {
            foreignKeyName: "items_org_code_fkey"
            columns: ["organization_code"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["organization_code"]
          },
        ]
      }
      login_logs: {
        Row: {
          device_name: string | null
          id: number
          login_time: string | null
          organization_code: string | null
          os_version: string | null
          role: string
          worker_id: string
        }
        Insert: {
          device_name?: string | null
          id?: number
          login_time?: string | null
          organization_code?: string | null
          os_version?: string | null
          role: string
          worker_id: string
        }
        Update: {
          device_name?: string | null
          id?: number
          login_time?: string | null
          organization_code?: string | null
          os_version?: string | null
          role?: string
          worker_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "login_logs_worker_id_fkey"
            columns: ["worker_id"]
            isOneToOne: false
            referencedRelation: "workers"
            referencedColumns: ["worker_id"]
          },
        ]
      }
      machines: {
        Row: {
          created_at: string
          id: string
          machine_id: string
          name: string
          organization_code: string | null
          type: string
        }
        Insert: {
          created_at?: string
          id?: string
          machine_id: string
          name: string
          organization_code?: string | null
          type: string
        }
        Update: {
          created_at?: string
          id?: string
          machine_id?: string
          name?: string
          organization_code?: string | null
          type?: string
        }
        Relationships: [
          {
            foreignKeyName: "machines_org_code_fk"
            columns: ["organization_code"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["organization_code"]
          },
          {
            foreignKeyName: "machines_org_code_fkey"
            columns: ["organization_code"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["organization_code"]
          },
        ]
      }
      notifications: {
        Row: {
          body: string
          created_at: string | null
          id: string
          organization_code: string
          read: boolean | null
          title: string
          type: string | null
          worker_id: string | null
          worker_name: string | null
        }
        Insert: {
          body: string
          created_at?: string | null
          id?: string
          organization_code: string
          read?: boolean | null
          title: string
          type?: string | null
          worker_id?: string | null
          worker_name?: string | null
        }
        Update: {
          body?: string
          created_at?: string | null
          id?: string
          organization_code?: string
          read?: boolean | null
          title?: string
          type?: string | null
          worker_id?: string | null
          worker_name?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "notifications_worker_id_fkey"
            columns: ["worker_id"]
            isOneToOne: false
            referencedRelation: "workers"
            referencedColumns: ["worker_id"]
          },
        ]
      }
      organizations: {
        Row: {
          address: string | null
          factory_name: string
          id: number
          latitude: number | null
          logo_url: string | null
          longitude: number | null
          organization_code: string
          organization_name: string
          owner_password: string
          owner_username: string
          radius_meters: number | null
        }
        Insert: {
          address?: string | null
          factory_name: string
          id?: number
          latitude?: number | null
          logo_url?: string | null
          longitude?: number | null
          organization_code: string
          organization_name: string
          owner_password: string
          owner_username: string
          radius_meters?: number | null
        }
        Update: {
          address?: string | null
          factory_name?: string
          id?: number
          latitude?: number | null
          logo_url?: string | null
          longitude?: number | null
          organization_code?: string
          organization_name?: string
          owner_password?: string
          owner_username?: string
          radius_meters?: number | null
        }
        Relationships: []
      }
      owner_logs: {
        Row: {
          device_name: string | null
          id: number
          login_time: string
          organization_code: string | null
          os_version: string | null
        }
        Insert: {
          device_name?: string | null
          id?: number
          login_time: string
          organization_code?: string | null
          os_version?: string | null
        }
        Update: {
          device_name?: string | null
          id?: number
          login_time?: string
          organization_code?: string | null
          os_version?: string | null
        }
        Relationships: []
      }
      production_logs: {
        Row: {
          created_at: string
          created_by_supervisor: boolean | null
          end_time: string | null
          id: string
          is_active: boolean | null
          is_verified: boolean | null
          item_id: string
          latitude: number | null
          longitude: number | null
          machine_id: string
          operation: string
          organization_code: string | null
          performance_diff: number | null
          quantity: number
          remarks: string | null
          shift_name: string | null
          start_time: string | null
          supervisor_id: string | null
          supervisor_quantity: number | null
          timestamp: string | null
          verified_at: string | null
          verified_by: string | null
          verified_note: string | null
          worker_id: string
        }
        Insert: {
          created_at?: string
          created_by_supervisor?: boolean | null
          end_time?: string | null
          id?: string
          is_active?: boolean | null
          is_verified?: boolean | null
          item_id: string
          latitude?: number | null
          longitude?: number | null
          machine_id: string
          operation: string
          organization_code?: string | null
          performance_diff?: number | null
          quantity: number
          remarks?: string | null
          shift_name?: string | null
          start_time?: string | null
          supervisor_id?: string | null
          supervisor_quantity?: number | null
          timestamp?: string | null
          verified_at?: string | null
          verified_by?: string | null
          verified_note?: string | null
          worker_id: string
        }
        Update: {
          created_at?: string
          created_by_supervisor?: boolean | null
          end_time?: string | null
          id?: string
          is_active?: boolean | null
          is_verified?: boolean | null
          item_id?: string
          latitude?: number | null
          longitude?: number | null
          machine_id?: string
          operation?: string
          organization_code?: string | null
          performance_diff?: number | null
          quantity?: number
          remarks?: string | null
          shift_name?: string | null
          start_time?: string | null
          supervisor_id?: string | null
          supervisor_quantity?: number | null
          timestamp?: string | null
          verified_at?: string | null
          verified_by?: string | null
          verified_note?: string | null
          worker_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "production_logs_item_id_fkey"
            columns: ["item_id", "organization_code"]
            isOneToOne: false
            referencedRelation: "items"
            referencedColumns: ["item_id", "organization_code"]
          },
          {
            foreignKeyName: "production_logs_machine_id_fkey"
            columns: ["machine_id", "organization_code"]
            isOneToOne: false
            referencedRelation: "machines"
            referencedColumns: ["machine_id", "organization_code"]
          },
          {
            foreignKeyName: "production_logs_org_code_fk"
            columns: ["organization_code"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["organization_code"]
          },
          {
            foreignKeyName: "production_logs_org_code_fkey"
            columns: ["organization_code"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["organization_code"]
          },
          {
            foreignKeyName: "production_logs_worker_id_fkey"
            columns: ["worker_id", "organization_code"]
            isOneToOne: false
            referencedRelation: "workers"
            referencedColumns: ["worker_id", "organization_code"]
          },
        ]
      }
      production_outofbounds: {
        Row: {
          created_at: string | null
          date: string
          duration_minutes: string | null
          entry_latitude: number | null
          entry_longitude: number | null
          entry_time: string | null
          exit_latitude: number | null
          exit_longitude: number | null
          exit_time: string
          id: string
          organization_code: string
          worker_id: string | null
          worker_name: string | null
        }
        Insert: {
          created_at?: string | null
          date: string
          duration_minutes?: string | null
          entry_latitude?: number | null
          entry_longitude?: number | null
          entry_time?: string | null
          exit_latitude?: number | null
          exit_longitude?: number | null
          exit_time?: string
          id: string
          organization_code: string
          worker_id?: string | null
          worker_name?: string | null
        }
        Update: {
          created_at?: string | null
          date?: string
          duration_minutes?: string | null
          entry_latitude?: number | null
          entry_longitude?: number | null
          entry_time?: string | null
          exit_latitude?: number | null
          exit_longitude?: number | null
          exit_time?: string
          id?: string
          organization_code?: string
          worker_id?: string | null
          worker_name?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "production_outofbounds_worker_id_fkey"
            columns: ["worker_id"]
            isOneToOne: false
            referencedRelation: "workers"
            referencedColumns: ["worker_id"]
          },
        ]
      }
      shifts: {
        Row: {
          created_at: string
          end_time: string
          id: string
          name: string
          organization_code: string | null
          start_time: string
        }
        Insert: {
          created_at?: string
          end_time: string
          id?: string
          name: string
          organization_code?: string | null
          start_time: string
        }
        Update: {
          created_at?: string
          end_time?: string
          id?: string
          name?: string
          organization_code?: string | null
          start_time?: string
        }
        Relationships: [
          {
            foreignKeyName: "shifts_org_code_fk"
            columns: ["organization_code"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["organization_code"]
          },
        ]
      }
      work_assignments: {
        Row: {
          assigned_by: string
          created_at: string | null
          id: string
          item_id: string
          machine_id: string
          operation: string
          organization_code: string
          status: string
          updated_at: string | null
          worker_id: string
        }
        Insert: {
          assigned_by: string
          created_at?: string | null
          id?: string
          item_id: string
          machine_id: string
          operation: string
          organization_code: string
          status?: string
          updated_at?: string | null
          worker_id: string
        }
        Update: {
          assigned_by?: string
          created_at?: string | null
          id?: string
          item_id?: string
          machine_id?: string
          operation?: string
          organization_code?: string
          status?: string
          updated_at?: string | null
          worker_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "work_assignments_item_id_fkey"
            columns: ["item_id", "organization_code"]
            isOneToOne: false
            referencedRelation: "items"
            referencedColumns: ["item_id", "organization_code"]
          },
          {
            foreignKeyName: "work_assignments_machine_id_fkey"
            columns: ["machine_id", "organization_code"]
            isOneToOne: false
            referencedRelation: "machines"
            referencedColumns: ["machine_id", "organization_code"]
          },
          {
            foreignKeyName: "work_assignments_org_code_fkey"
            columns: ["organization_code"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["organization_code"]
          },
          {
            foreignKeyName: "work_assignments_organization_code_fkey"
            columns: ["organization_code"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["organization_code"]
          },
          {
            foreignKeyName: "work_assignments_worker_id_fkey"
            columns: ["worker_id"]
            isOneToOne: false
            referencedRelation: "workers"
            referencedColumns: ["worker_id"]
          },
        ]
      }
      worker_boundary_events: {
        Row: {
          created_at: string | null
          duration_minutes: string | null
          entry_latitude: number | null
          entry_longitude: number | null
          entry_time: string | null
          exit_latitude: number | null
          exit_longitude: number | null
          exit_time: string | null
          id: string
          is_inside: boolean | null
          latitude: number | null
          longitude: number | null
          organization_code: string
          remarks: string | null
          type: string
          worker_id: string
        }
        Insert: {
          created_at?: string | null
          duration_minutes?: string | null
          entry_latitude?: number | null
          entry_longitude?: number | null
          entry_time?: string | null
          exit_latitude?: number | null
          exit_longitude?: number | null
          exit_time?: string | null
          id: string
          is_inside?: boolean | null
          latitude?: number | null
          longitude?: number | null
          organization_code: string
          remarks?: string | null
          type?: string
          worker_id: string
        }
        Update: {
          created_at?: string | null
          duration_minutes?: string | null
          entry_latitude?: number | null
          entry_longitude?: number | null
          entry_time?: string | null
          exit_latitude?: number | null
          exit_longitude?: number | null
          exit_time?: string | null
          id?: string
          is_inside?: boolean | null
          latitude?: number | null
          longitude?: number | null
          organization_code?: string
          remarks?: string | null
          type?: string
          worker_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "fk_boundary_org"
            columns: ["organization_code"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["organization_code"]
          },
          {
            foreignKeyName: "fk_worker_boundary_events_workers"
            columns: ["worker_id"]
            isOneToOne: false
            referencedRelation: "workers"
            referencedColumns: ["worker_id"]
          },
          {
            foreignKeyName: "worker_boundary_events_worker_id_fkey"
            columns: ["worker_id"]
            isOneToOne: false
            referencedRelation: "workers"
            referencedColumns: ["worker_id"]
          },
        ]
      }
      worker_breaks: {
        Row: {
          break_type: string | null
          created_at: string | null
          duration_minutes: number | null
          end_time: string | null
          id: string
          organization_code: string
          start_time: string
          worker_id: string
        }
        Insert: {
          break_type?: string | null
          created_at?: string | null
          duration_minutes?: number | null
          end_time?: string | null
          id?: string
          organization_code: string
          start_time?: string
          worker_id: string
        }
        Update: {
          break_type?: string | null
          created_at?: string | null
          duration_minutes?: number | null
          end_time?: string | null
          id?: string
          organization_code?: string
          start_time?: string
          worker_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "worker_breaks_organization_code_fkey"
            columns: ["organization_code"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["organization_code"]
          },
          {
            foreignKeyName: "worker_breaks_worker_id_fkey"
            columns: ["worker_id"]
            isOneToOne: false
            referencedRelation: "workers"
            referencedColumns: ["worker_id"]
          },
        ]
      }
      workers: {
        Row: {
          aadhar_card: string | null
          age: number | null
          avatar_url: string | null
          created_at: string
          id: string
          image_url: string | null
          mobile_number: string | null
          name: string
          organization_code: string | null
          pan_card: string | null
          password: string
          photo_url: string | null
          profile_photos: string | null
          role: string | null
          username: string
          worker_id: string
        }
        Insert: {
          aadhar_card?: string | null
          age?: number | null
          avatar_url?: string | null
          created_at?: string
          id?: string
          image_url?: string | null
          mobile_number?: string | null
          name: string
          organization_code?: string | null
          pan_card?: string | null
          password: string
          photo_url?: string | null
          profile_photos?: string | null
          role?: string | null
          username: string
          worker_id: string
        }
        Update: {
          aadhar_card?: string | null
          age?: number | null
          avatar_url?: string | null
          created_at?: string
          id?: string
          image_url?: string | null
          mobile_number?: string | null
          name?: string
          organization_code?: string | null
          pan_card?: string | null
          password?: string
          photo_url?: string | null
          profile_photos?: string | null
          role?: string | null
          username?: string
          worker_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "workers_org_code_fk"
            columns: ["organization_code"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["organization_code"]
          },
          {
            foreignKeyName: "workers_org_code_fkey"
            columns: ["organization_code"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["organization_code"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      attendance_check_in: {
        Args: {
          p_date: string
          p_org_code: string
          p_shift_end: string
          p_shift_name: string
          p_shift_start: string
          p_worker_id: string
        }
        Returns: undefined
      }
      attendance_check_out: {
        Args: { p_date: string; p_org_code: string; p_worker_id: string }
        Returns: undefined
      }
      calculate_duration_minutes: {
        Args: { end_t: string; start_t: string }
        Returns: string
      }
      handle_worker_return: {
        Args: { entry_lat: number; entry_lng: number; event_id: string }
        Returns: undefined
      }
      log_production_end: {
        Args: {
          p_id: string
          p_performance_diff: number
          p_quantity: number
          p_remarks: string
        }
        Returns: undefined
      }
      log_production_start: {
        Args: {
          p_id: string
          p_item_id: string
          p_lat: number
          p_lng: number
          p_machine_id: string
          p_operation: string
          p_org_code: string
          p_shift_name: string
          p_worker_id: string
        }
        Returns: undefined
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {},
  },
} as const
