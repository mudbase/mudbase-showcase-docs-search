import { QueryClient } from "@tanstack/react-query";
import { MudbaseApiError } from "@/api/client";

export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 1000 * 30,
      gcTime: 1000 * 60 * 60,
      retry: (failureCount, error) => {
        if (error instanceof MudbaseApiError && (error.statusCode === 401 || error.statusCode === 403)) {
          return false;
        }
        return failureCount < 2;
      },
      refetchOnReconnect: true,
    },
    mutations: {
      retry: 0,
    },
  },
});
