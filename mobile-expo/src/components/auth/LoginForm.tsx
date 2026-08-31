import { Controller, useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { View } from "react-native";
import { z } from "zod";
import { useAuth } from "@/hooks/useAuth";
import { TextField } from "@/components/ui/TextField";
import { Button } from "@/components/ui/Button";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

const loginSchema = z.object({
  email: z.string().min(1, "Email is required").email("Enter a valid email address"),
  password: z.string().min(1, "Password is required"),
});

type LoginFormValues = z.infer<typeof loginSchema>;

// Provisioned per the task's instructions - do not create additional demo accounts. Full CRUD on
// both collections comes from Mudbase's single default "customer" role (see plan/build-plan.md).
const DEMO_ACCOUNT = { email: "docs.member.demo@gmail.com", password: "DemoTest123!" } as const;

export function LoginForm({ onSuccess }: { onSuccess: () => void }): React.JSX.Element {
  const { login, isSubmitting, error, clearError } = useAuth();
  const {
    control,
    handleSubmit,
    setValue,
    formState: { errors },
  } = useForm<LoginFormValues>({ resolver: zodResolver(loginSchema), defaultValues: { email: "", password: "" } });

  const onSubmit = async (values: LoginFormValues): Promise<void> => {
    clearError();
    const ok = await login(values.email, values.password);
    if (ok) onSuccess();
  };

  const quickFill = async (): Promise<void> => {
    clearError();
    setValue("email", DEMO_ACCOUNT.email);
    setValue("password", DEMO_ACCOUNT.password);
    const ok = await login(DEMO_ACCOUNT.email, DEMO_ACCOUNT.password);
    if (ok) onSuccess();
  };

  return (
    <View className="gap-4">
      <Button variant="outline" disabled={isSubmitting} onPress={() => void quickFill()}>
        Use demo account
      </Button>

      {error && <ErrorNotice message={error} />}

      <Controller
        control={control}
        name="email"
        render={({ field: { onChange, onBlur, value } }) => (
          <TextField
            label="Email"
            value={value}
            onChangeText={onChange}
            onBlur={onBlur}
            keyboardType="email-address"
            autoCapitalize="none"
            autoComplete="email"
            placeholder="docs.member.demo@gmail.com"
            error={errors.email?.message}
          />
        )}
      />
      <Controller
        control={control}
        name="password"
        render={({ field: { onChange, onBlur, value } }) => (
          <TextField
            label="Password"
            value={value}
            onChangeText={onChange}
            onBlur={onBlur}
            secureTextEntry
            autoComplete="current-password"
            error={errors.password?.message}
          />
        )}
      />
      <Button onPress={handleSubmit(onSubmit)} isLoading={isSubmitting}>
        {isSubmitting ? "Signing in…" : "Sign in"}
      </Button>
    </View>
  );
}
