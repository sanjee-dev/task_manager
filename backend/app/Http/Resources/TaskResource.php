<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class TaskResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'task_uuid' => $this->id,
            'server_id' => $this->id,
            'title' => $this->title,
            'note' => $this->note,
            'start_datetime' => $this->start_datetime?->utc()->toISOString(),
            'end_datetime' => $this->end_datetime?->utc()->toISOString(),
            'status' => $this->status,
            'version' => $this->version,
            'created_at' => $this->created_at?->utc()->toISOString(),
            'updated_at' => $this->updated_at?->utc()->toISOString(),
            'deleted_at' => $this->deleted_at?->utc()->toISOString(),
        ];
    }
}
